using Gee;



namespace MyAppProtocol{
	/*
	static void print_bin(string name, uint8[] bin){
		int i = 0;
		print("=====%s(%zu)=====\n", name, bin.length);
		foreach(var b in bin){
			switch(i){
			case 8:
				print(" ");
				break;
			case 16:
				print("\n");
				i = 0;
				break;
			}
			print("%02x ", b);
			i++;
		}
		print("\n");
		return;
	}
	*/
	
	public class MpTimelineReceiver<T>: Receiver<T, double?>, GLib.Object {
		
		/// \note	どうやらこれをストリーミング的に使っていると危険らしいことが分かった。
		///			使用済みの分を綺麗にする手段がないってどういうことなの…
		//MessagePackの受信バッファ
		//private MessagePack.Unpacker mp;
		
		//パース/計算して得られた数値時系列。emitしたらそのあとクリアする。
		private Map<string, Gee.SortedSet<T>> series;
		
		//emitするとき、これを起点に「何秒まで」の時刻のデータを抽出するかを決定する
		private Map<string, int64?> base_timepoints;
		
		private Map<string, double?> last_read_values;
		
		//計算器オブジェクト。
		private Gee.List<Calculation.Calculator> calculators;
		
		GLib.CompareDataFunc<T>? sorter;
		
		TimelineMaker<T, double?>? tl_maker;
		
		TimestampGetter<T>? ts_getter;
		
		//バッファ。Unpackerがストリームバッファとしては役に立たないので、自己防衛おじさん。
		private uint8[] buffer;
		private size_t buffer_pushed;
		
		private Map<string, double?> coeffs;
		
		public MpTimelineReceiver (
			size_t buffer_size,
			GLib.CompareDataFunc<T> tl_sorter,
			TimelineMaker<T, double?> tl_maker,
			TimestampGetter<T> ts_getter
		){
			this.series = new HashMap<string, Gee.SortedSet<T>>();
			this.base_timepoints = new HashMap<string, int64?>();
			this.calculators = new Gee.LinkedList<Calculation.Calculator>();
			this.last_read_values = new Gee.HashMap<string, double?>();
			this.coeffs = new HashMap<string, double?>();
			this.buffer = new uint8[buffer_size];
			this.buffer_pushed = 0;
			
			this.sorter = tl_sorter;
			this.tl_maker = tl_maker;
			this.ts_getter = ts_getter;
			
		}
		
		public MpTimelineReceiver copy_template(){
			var template = this;
			var ret = new MpTimelineReceiver<T>(template.buffer.length, template.sorter, template.tl_maker, template.ts_getter);
			foreach(var entry in template.coeffs.entries){
				var name = entry.key;
				var coeff = entry.value;
				ret.define_series(name, coeff);
			}
			
			foreach(var c in template.calculators){
				ret.calculators.add(c.copy());
			}
			
			ret.calculators.sort(Calculation.Calculator.sorter);
			foreach(var ent in template.series.entries){
				ret.set_as_plottee(ent.key, true);
			}
			return ret;
		}
		
		//パケットを詰め込む。パースエラーを起こさないシロモノならtrue。
		//理想的には、parsedに「この時点をもって正しくパースできたバイナリ」が入る。
		//MessagePackの場合・・・、unpacker.buffer()とunpacker.parsed_size()でも使うか？
		//public ssize_t push(uint8[] packet, ref uint8[] parsed, out int64 start_time){
		public ssize_t push(uint8[] packet, CaptureParsed? capture_parsed = null){
			
			if(packet.length <= 0){
				return -1;
			}
			
			size_t onset = 0;
			ssize_t ret_len = 0;
			MessagePack.Unpacked pac = MessagePack.Unpacked();
			
			if((this.buffer.length - this.buffer_pushed) < packet.length){
				//print("extend buffer. prev is %zd\n".printf(this.buffer.length));
				// 次に来たデータでバッファをはみ出してしまう場合。
				// →べき乗式でメモリを広げる。
				size_t t_len = this.buffer.length;
				while((t_len - this.buffer_pushed) < packet.length){
					t_len *= 2;
				}
				var new_buf = new uint8[t_len];
				Memory.copy(new_buf, this.buffer, this.buffer_pushed);
				this.buffer = new_buf;
			}
			
			//print("buf size: %zd\n".printf(this.buffer.length));
			//次、自前のバッファに新しくやってきた分のパケットをコピーする
			Memory.copy(&(this.buffer[this.buffer_pushed]), packet, packet.length);
			this.buffer_pushed += packet.length;
			
			// パース方法をUnpacked + 固定バッファに切り替えたため、
			// 「その時パースされたエリア」の特定が楽になりました
			for(;;){
				size_t outlen = 0;
				//print("parse %zu to %zu\n".printf(onset, this.buffer_pushed));
				var res = pac.next(this.buffer[onset: this.buffer_pushed], out outlen);
				switch(res){
				case MessagePack.UnpackReturn.SUCCESS:
				case MessagePack.UnpackReturn.EXTRA_BYTES:
					//print("read %zu bytes\n".printf(outlen));
					//データをきちんと読み込めたことを示す…らしい。
					//pac.data.print(GLib.stdout);
					int64 ts = 0L;
					if(this.treat_unpacked(ref pac.data, out ts)){
						if(capture_parsed != null){
							capture_parsed(this.buffer[onset: onset + outlen], ts);
						}
					}
					//終わったら生成したデータは掃除してあげること。
					pac.release_zone();
					onset += outlen;
					continue;
				case MessagePack.UnpackReturn.CONTINUE:
					pac.release_zone();
					break;
				default:
					//print("may be wrong packet\n");
					//パースエラーやメモリが足りないという理由でエラーを起こす
					pac.release_zone();
					return -1;
				}
				break;
			}
			
			ret_len = (ssize_t)onset;
			//最終的にデコードされた分をparsedに打ち込む。
			//Memory.copy(parsed, this.buffer, ret_len);
			
			//次の「プッシュ済みバッファ」の長さを決める
			//print("pushed%zu vs ret%zd\n".printf(this.buffer_pushed, ret_len));
			if(ret_len > 0 && ret_len < this.buffer_pushed){
				//残ったパケットデータがある場合
				//print("->memmove\n");
				this.buffer_pushed = this.buffer_pushed - ret_len;
				Memory.move(this.buffer, &(this.buffer[ret_len]), this.buffer_pushed);
			}
			else{
				this.buffer_pushed = 0;
			}
			//print("next pushed is %zu\n".printf(this.buffer_pushed));
			/*
			if(unpacker.message_size() > 0){
				//デコードされた分をbufferから退去させる
				Memory.move(this.buffer, &(this.buffer[ret_len]), unpacker.message_size());
				//assert(ret_len + unpacker.message_size() == packet.length);
			}
			this.buffer_pushed = unpacker.message_size();
			*/
			return ret_len;
		}
		
		private bool treat_unpacked(ref MessagePack.Object decoded, out int64 ts){
			int64 timestamp = -1L;
			
			bool time_got = false;
			uint8 nbuf[128];
			unowned string name;
			MessagePack.MapEntry[] vEntries = null;
			
			if(decoded.type != MessagePack.Type.MAP){
				return false;
			}
			//print("\n");
			//思ったんだけど、ここでのmessagepackの読み方がなかなかに原始的だぞう
			foreach(var entry in decoded.map.entries){
				var k = entry.key;		//"t" or "v"
				var v = entry.value;	//int64 or object
				if(k.type != MessagePack.Type.STR){
					continue;
				}
				if(nbuf.length <= k.str.str.length){
					continue;
				}
				Memory.copy(nbuf, k.str.str, k.str.str.length);
				nbuf[k.str.str.length] = 0;
				name = (string)nbuf;
				
				if(name == "t"){
					if(v.type == MessagePack.Type.POSITIVE_INTEGER || v.type == MessagePack.Type.NEGATIVE_INTEGER){
						time_got = true;
						timestamp = v.i64;
						ts = timestamp;
						//print("get timestamp->%lld\n".printf(timestamp));
					}
					else{
						//違う構造しているならとっとと帰りましょう
						break;
					}
				}
				else if(name == "v"){
					//実際の値はまだ。
					//print("get value\n");
					if(v.type != MessagePack.Type.MAP){
						break;
					}
					vEntries = v.map.entries;
				}
				//他の値を投げられるかもしれないけど、今は無視
				continue;
			}
			if(vEntries == null || !time_got){
				return false;
			}
			
			//print("getting values\n");
			foreach(var entry in vEntries){
				//実際の値をここであれこれいじくるぞ
				var k = entry.key;
				var v = entry.value;
				var val = double.NAN;
			
				if(k.type != MessagePack.Type.STR){
					continue;
				}
				if(nbuf.length <= k.str.str.length){
					continue;
				}
				Memory.copy(nbuf, k.str.str, k.str.str.length);
				nbuf[k.str.str.length] = 0;
				name = (string)nbuf;
				//print("%s(%u)->%d\n".printf(name, name.length, v.type));
				if(!this.last_read_values.has_key(name)){
					continue;
				}
				
				var coeff = this.coeffs.get(name);
				switch(v.type){
				case MessagePack.Type.POSITIVE_INTEGER:
				case MessagePack.Type.NEGATIVE_INTEGER:
					val = (double)(coeff * v.i64);
					break;
				case MessagePack.Type.FLOAT:
				case 10:
					val = (double) coeff * v.f64;
					break;
				case MessagePack.Type.BOOLEAN:
					val = v.boolean ? (double)coeff : 0.0;
					break;
				default:
					break;
				}
				
				if(!val.is_nan()){
					//print("%s@%lld->%f\n".printf(name, timestamp, val));
					T point = this.tl_maker(timestamp, val);
					this.last_read_values[name] = val;
					this.series[name]?.add(point);
				}
			}
			
			foreach(var c_entry in this.calculators){
				var calc_name = c_entry.name;
				var calculator = c_entry;
				var coeff = this.coeffs.get(calc_name);
				//print("Calculate %s\n".printf(calc_name));
				if(!this.last_read_values.has_key(calc_name)){
					continue;
				}
				
				/// \note 微分を実装してみたけど使い勝手悪いのでボツ.
				//calculator.set_current_timepoint(timestamp);
				var val = calculator.calculate((name) => {
					if(this.last_read_values.has_key(name)){
						return this.last_read_values[name];
					}
					return 0.0;
				});
				
				if(!val.is_nan()){
					T tv = this.tl_maker(timestamp, (double)(val * coeff));
					this.last_read_values[calc_name] = val;
					this.series[calc_name]?.add(tv);
				}
			}
			return true;
		}
		
		//時系列を一つ登録する。それ以外は読み捨てることを実装者は約束する。
		public bool define_series(string name, double coeff){
			if(this.last_read_values.has_key(name)){
				return false;
			}
			
			this.coeffs.set(name, coeff);
			this.last_read_values.set(name, 0.0);
			return true;
		}
		
		//OnEmitで指定された関数を呼び出す。
		public void emit(OnEmit<T>? on_emit, int64 threshold_ms = -1){
			if(threshold_ms <= 0){
				//全部参照する
				foreach(var entry in this.series.entries){
					var serie = entry.value;
					var name = entry.key;
					this.base_timepoints.unset(entry.key);
					if(on_emit == null || on_emit(name, serie.read_only_view)){
						serie.clear();
					}
				}
			}
			else{
				//一定の起点からthreshold_msの分だけ参照する
				foreach(var entry in this.series.entries){
					unowned var serie = entry.value;
					var name = entry.key;
					bool already_read = this.base_timepoints.has_key(name);
					int64 ts;
					//値が一個でも入っているかをチェックする
					//print("===================\n");
					if(serie.size <= 0 && !already_read){
						//入っていないなら無視する
						continue;
					}
					if(!already_read){
						//一度も読んだことがないのなら、現状入っているものの最初を起点とする。
						this.base_timepoints[name] = this.ts_getter(serie.first());
					}
					//border_point.timepoint = this.base_timepoints[name] + threshold_ms;
					ts = this.base_timepoints[name] + threshold_ms;
					this.base_timepoints[name] = ts;
					
					//TreeSetを分割するための基準点
					T border_point = this.tl_maker(ts, 0.0);
					
					//print("%s: border time: %lld\n".printf(name, border_point.timepoint));
					
					//border_point.timepointを起点にした頭をとる。
					var head_set = serie.head_set(border_point);
					if(head_set.size <= 0){
						//print("%s->no head\n".printf(name));
						continue;
					}
					/*
					foreach(var v in head_set){
						print("%s(head)->%lld - %f vs %lld\n".printf(name, v.timepoint, v.data, border_point.timepoint));
					}
					*/
					if(on_emit == null || on_emit(name, head_set)){
						head_set.clear();
					}
				}
			}
		}
		
		//保存されている時系列について、実際に値を削除せずに参照する
		public void refer_ranged(OnEmit<T>? on_emit, int64 start, int64 end){
			T start_point = this.tl_maker(start, 0.0);
			T end_point = this.tl_maker(end, 0.0);
			foreach(var entry in this.series.entries){
				unowned var serie = entry.value;
				var r = serie.sub_set(start_point, end_point);
				if(on_emit != null){
					on_emit(entry.key, r.read_only_view);
				}
			}
		}
		
		public bool define_calc(string calc_name, string method, double coeff, int priority){
			var c = Calculation.Calculator.new_by_name(method);
			if(c == null){
				return false;
			}
			if(this.last_read_values.has_key(calc_name)){
				return false;
			}
			this.define_series(calc_name, coeff);
			c.name = calc_name;
			c.priority = priority;
			this.calculators.add(c);
			this.calculators.sort(Calculation.Calculator.sorter);
			
			return true;
		}
		
		public bool put_calc_arg(string calc_name, string arg_name, double shift){
			foreach(var c in this.calculators){
				if(c.name != calc_name){
					continue;
				}
				c.register_arg(arg_name, shift);
				return true;
			}
			return false;
		}
		
		public bool put_calc_const(string calc_name, string const_name, string const_value){
			foreach(var c in this.calculators){
				if(c.name != calc_name){
					continue;
				}
				c.set_const_value(const_name, const_value);
				return true;
			}
			return false;
		}
		
		public bool set_as_plottee(string name, bool for_plot){
			
			if(!this.last_read_values.has_key(name)){
				return false;
			}
			
			if(for_plot && !this.series.has_key(name)){
				this.series.set(name, new Gee.TreeSet<T>(this.sorter));
				return true;
			}
			else if(!for_plot){
				return this.series.unset(name);
			}
			return false;
		}
		
	}
}
