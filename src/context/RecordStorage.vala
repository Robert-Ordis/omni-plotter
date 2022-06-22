/*
・「現在の録画開始地点」を覚えておく。可能ならそのひとつ前も。

・録画開始地点が更新されたら、昔の一歩前のところまでは捨ててしまう
　→この処理は、パケット受信しなければそもそも働かない。のでprotocol="file"では呼ばれない

・で、シーク時に自分の録画地点より前であり、ロードされていなそうダったらファイル読み出しをリクエスト

・シークしたら、まずはどの地点のデータを読み出すべきなのかを把握しておく。
　→シーク地点のインデックスを特定したら、少しタスクを遅らせる。
　　→インデックスが変わらないならファイル読み込み開始
　→できるなら、シーク地点のインデックスと、その次を読んでおきたい
　→一度把握したら、次にファイル読み出しやデータの転写をしなくて良くするため。

*/

namespace MyContext{
	
	static void print_bin(string name, uint8[] bin){
		int i = 0;
		//print("=====%s(%zu)=====\n", name, bin.length);
		foreach(var b in bin){
			switch(i){
			case 8:
				//print(" ");
				break;
			case 16:
				//print("\n");
				i = 0;
				break;
			}
			//print("%02x ", b);
			i++;
		}
		//print("\n");
		return;
	}
	
	public class RecordStorage{
		
		private class IndexReader{
			public int64	index = -0x7FFFFFFFFFFFFFFF;
			public string filename = "";
			
			//デコーダー。並列して読もうと思ったら、デコーダーも別々に用意する必要がある。
			private MyAppProtocol.MpTimelineReceiver? receiver = null;
			private MyAppProtocol.OnEmit on_emit = null;
			private GLib.IOChannel? channel = null;
			private uint channel_task = 0;
			
			private unowned uint8[] read_buffer;
			private unowned uint8[] parsed_buffer;
			
			public static int cmp_(IndexReader a, IndexReader b){
				int64 r = a.index - b.index;
				if(r > 0){
					return 1;
				}
				else if(r < 0){
					return -1;
				}
				return 0;
			}
			
			public void reserve_task(RecordStorage parent, MyAppProtocol.OnEmit on_emit, uint delay){
				
				this.channel = new GLib.IOChannel.file(this.filename, "r");
				this.channel.set_encoding(null);
				////print("setup task 4 %llX(%s)\n".printf(idx.index, idx.filename));
				
				//idx.receiverを、雛形をもって作成する
				this.receiver = parent.reader_template.copy_template();
				this.on_emit = on_emit;
				this.read_buffer = parent.read_buffer;
				this.parsed_buffer = parent.parsed_buffer;
				
				if(delay <= 0){
					delay = 1;
				}
				this.channel_task = GLib.Timeout.add(delay, () => {
					this.channel_task = this.channel.add_watch(GLib.IOCondition.IN, (source, condition) => {
						//ファイルを読み込み
						//読み込んで出てきたバイナリをreaderにとにかく突っ込む
						////print("%s\n".printf(ok ? "OK" : "NG"));
						bool ret = false;
						GLib.IOStatus ioret = GLib.IOStatus.ERROR;
						try{
							string dat_str;
							size_t read_len = 0;
							//var ioret = source.read_line(out dat_str, out read_len, null);
							ioret = source.read_chars((char[])this.read_buffer, out read_len);
							if(ioret == GLib.IOStatus.NORMAL || ioret == GLib.IOStatus.AGAIN){
								ret = true;
							}
							
							//print_bin("test", this.read_buffer);
							//print("read %s [%zu]:\n".printf(this.filename, read_len));
							
							if(read_len > 0){
								//ここで、readerに突っ込む処理を入れる。
								//バイナリはたぶん、dat_str.dataで手に入る…はず。
								var buf = this.read_buffer;
								var pbuf = this.parsed_buffer;
								
								size_t from_ = 0;
								size_t to_;
								int64 start_time = -0x7FFFFFFFFFFFFFFF;
								while(from_ < read_len){
									to_ = from_ + this.parsed_buffer.length;
									if(to_ > read_len){
										to_ = read_len;
									}
									var tell = buf[from_: to_];
									////print("idx.receiver is %s\n".printf((idx.receiver == null) ? "NULL" : "inst"));
									//this.receiver.push(tell, ref pbuf, out start_time);
									this.receiver.push(tell);
									////print("push tell.%d\n".printf(tell.length));
									from_ = to_;
								}
								
							}
							
						}
						catch(GLib.Error e){}
						if(!ret){
							//print("%lld(%llx)->cancel on read end:%d\n".printf(this.index, this.index, ioret));
							//print("EOF is %d\n".printf(GLib.IOStatus.EOF));
							this.receiver.emit(this.on_emit);
							this.cancel();
						}
						return ret;
					});
					
					return false;
				});
				
				
			}
			
			public void cancel(){
				//print("canceling %llX\n".printf(this.index));
				if(this.channel != null){
					try{
						this.channel.shutdown(true);
						this.channel = null;
					}catch(GLib.Error e){}
				}
				if(this.channel_task != 0){
					GLib.Source.remove(this.channel_task);
					this.channel_task = 0;
				}
			}
			
		}
		
		//読み込みインデックス含めてあれこれ作ってくれてる理解あるレコーダー君
		public MyAppProtocol.PacketRecorder recorder{get; private set;}
		public MyAppProtocol.MpTimelineReceiver reader_template {get; private set;}
		
		//現在のストリーミングポイント（もしかしたら必要ないかもしれない）
		int64 index_recording = -0x7FFFFFFFFFFFFFFF;
		bool index_recording_modified = false;
		
		//現在、外に出させているインデックス群。
		Gee.SortedSet<IndexReader> indexes_seeking = new Gee.TreeSet<IndexReader>(IndexReader.cmp_);
		Gee.HashMap<GLib.IOChannel, IndexReader> channel_to_index = new Gee.HashMap<GLib.IOChannel, IndexReader>();
		
		IndexReader from_searcher = new IndexReader();
		IndexReader to_searcher = new IndexReader();
		
		uint8[] read_buffer;
		uint8[] parsed_buffer;
		
		uint read_task = 0;
		
		//シークポイント等の精査の結果、メモリ開放の命令を受けた場合に呼ばれる
		public signal void on_request_release(int64 from_timestamp, int64 to_timestamp);
		
		//シークポイントの精査。trueで読み込みを行う。falseで読み込みはしない（≒記録をしていない）
		public signal bool on_notifying_seekpoint(out int64 from_timestamp, out int64 to_timestamp, out MyAppProtocol.OnEmit on_emit);
		
		public RecordStorage(
			MyAppProtocol.PacketRecorder recorder, 
			MyAppProtocol.MpTimelineReceiver receiver, 
			size_t buffer_size,
			int period_ms
		){
			
			//シーク状態の読み込みタスクを取り付ける。
			if(period_ms <= 0){
				period_ms = 250;
			}
			this.recorder = recorder;
			this.reader_template = receiver;
			this.read_task = GLib.Timeout.add(period_ms, () => {
				int64 from_ts = 0;
				int64 to_ts = 0;
				MyAppProtocol.OnEmit? on_emit = null;
				if(!this.on_notifying_seekpoint(out from_ts, out to_ts, out on_emit)){
					//何かするべきかな。indexes_seekingの破棄でもする？
					return true;
				}
				this.notify_seek(from_ts, to_ts, on_emit);
				return true;
			});
			this.read_buffer = new uint8[buffer_size];
			this.parsed_buffer = new uint8[buffer_size * 2];
		}
		
		~RecordStorage(){
			//デストラクタ
			this.on_cancel();
		}
		
		//(index_from, index_to);
		private void notify_seek(int64 from_index, int64 to_index, MyAppProtocol.OnEmit? on_emit){
			//print("############\n\n\n\n");
			var tmpSet = new Gee.TreeSet<IndexReader>(IndexReader.cmp_);
			//1: this.recorderからfrom_indexを持つところ、to_indexを含むところ+1を抽出する。
			this.recorder.each_indexes_ranged(from_index, to_index,(first_time, each_file, is_completed) => {
				var tmp = new IndexReader();
				tmp.index = first_time;
				tmp.filename = each_file;
				//print("subjected range- %lld - %s \n".printf(first_time, each_file));
				if(is_completed && this.index_recording != first_time){
					//「録音中」は絶対に読み込みリストには入れない。
					tmpSet.add(tmp);
				}
				return is_completed;
			});
			
			//print("pulled out total: %d\n".printf(tmpSet.size));
			//2-1: indexes_seekingから、1をもとに「外すところ」を探る。
			if(tmpSet.size <= 0){
				//全部が削除対象
				var it = this.indexes_seeking.iterator();
				while(it.valid){
					var idx = it.get();
					if(idx.index != this.index_recording){
						idx.cancel();
					}
					it.next();
				}
				return;
			}
			
			if(false){
				print("============seeking======\n");
				foreach(var idx in this.indexes_seeking){
					print("%llx\n".printf(idx.index));
				}
			
				print("============nextlist======\n");
				foreach(var idx in tmpSet){
					print("%llx\n".printf(idx.index));
				}
			}
			
			do{
				IndexReader idx_curr, idx_next;
				//トリミング
				if(this.indexes_seeking.size <= 0){
					//「シーク中」に登録されているインデックスがないなら何もしない
					break;
				}
				
				//「現在シーク中」から先頭の余分を削除する
				idx_curr = this.indexes_seeking.first();
				idx_next = tmpSet.first();
				//わざわざ先頭を取ってるのは比較回数の低減を試みてのこと
				if(idx_curr.index < idx_next.index){
					//次読み込むリストの最初が現在の最初よりも進んでいた→差分を削除する
					var subset = this.indexes_seeking.head_set(idx_next);
					//print("delete seeking subset(head): %d\n".printf(subset.size));
					foreach(var idx in subset){
						idx.cancel();
					}
					
					subset.clear();
					
					//ないとは思うが、記録中のやつのの配慮
					if(idx_curr.index <= this.index_recording && this.index_recording <= idx_next.index){
						this.on_request_release(idx_curr.index, this.index_recording);
					}
					else{
						//先頭の不要データの削除要請
						this.on_request_release(idx_curr.index, idx_next.index);
					}
				}
				
				//「シーク中」が全部消えたのなら終了。
				if(this.indexes_seeking.size <= 0){
					break;
				}
				
				//「現在シーク中」から末尾の余分を削除する
				idx_curr = this.indexes_seeking.last();
				idx_next = tmpSet.last();
				if(idx_next.index < idx_curr.index){
					//次読み込むリストの最後が現在の最初よりも前だった→差分を削除する
					var subset = this.indexes_seeking.tail_set(idx_next);
					var padding = this.recorder.average_period;
					//print("delete seeking subset(tail): %d\n".printf(subset.size));
					foreach(var idx in subset){
						idx.cancel();
					}
					
					subset.clear();
					
					if(idx_next.index <= this.index_recording && this.index_recording <= idx_curr.index){
						this.on_request_release(this.index_recording + padding, idx_curr.index + padding);
					}
					else{
						//末尾の不要データの削除要請。
						this.on_request_release(idx_next.index + padding, idx_curr.index + padding);
					}
				}
				
				//「シーク中」が全部消えたのなら終了。
				if(this.indexes_seeking.size <= 0){
					break;
				}
				
				this.from_searcher.index = this.indexes_seeking.first().index;
				this.to_searcher.index = this.indexes_seeking.last().index + 1;
				//「現在シーク中」の余分を全部取ったので、次は「次回読み込み」から余分を取る
				//ここでの余分は、「現在シーク中とかぶっているエリア」になる。
				tmpSet.sub_set(this.from_searcher, this.to_searcher).clear();
				
			}while(false);
			
			
			
			//print("then, prepare to read %d indexes\n".printf(tmpSet.size));
			//ここまで来たら「indexes_seeking」に含まれていないところを特定できているので読み込み開始処理を付ける
			//3: indexes_seekingに「含まれていないところ」を追加し、それを読み込ませる処理をリクエスト。
			uint delay = 0;
			foreach(var idx in tmpSet){
				//idxに対して、読み込み開始処理を付ける
				bool ok = false;
				try{
					
					idx.reserve_task(this, on_emit, delay);
					
					this.indexes_seeking.add(idx);
					ok = true;
					delay += 50;
				}
				catch(GLib.Error e){
					
				}
				finally{
					if(!ok){
						idx.cancel();
					}
				}
			}
			
			//print("record index is %lld(%llx), modified->%s\n".printf(this.index_recording, this.index_recording, this.index_recording_modified ? "true": "false"));
			if(this.index_recording_modified){
				var t = -0x7FFFFFFFFFFFFFFF;
				if(this.indexes_seeking.size > 0){
					t = this.indexes_seeking.last().index + this.recorder.average_period;
				}
				
				if(t < this.index_recording){
					//print("%llX vs %llX\n".printf(t, this.index_recording));
					//記録中のインデックスがシークエリアよりも先に進んでいたら、そこから前は消すよう働きかける
					this.on_request_release(t, this.index_recording);
				}
				
				this.index_recording_modified = false;
			}
			
		}
		
		public void notify_index_recording(int64 val){
			if(!this.index_recording_modified){
				this.index_recording_modified = (val != this.index_recording);
			}
			this.index_recording = val;
		}
		
		//役目終了時。多分自分で抱えるタイマーだとかIOChannelだとかを全部外す。
		public void on_cancel(){
			if(this.read_task != 0){
				GLib.Source.remove(this.read_task);
			}
			this.read_task = 0;
			foreach(var idx in this.indexes_seeking){
				idx.cancel();
			}
		}
	}
	
}