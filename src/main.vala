
public class TopContext {
	
	public class Receiving {
		public GLib.Socket sock = null;
		public GLib.IOChannel channel = null;
		public uint channel_task = 0;
		public uint8[] buf;
		public MyAppProtocol.MpTimelineReceiver<LiveChart.TimestampedValue?> parser = null;
		public uint emit_task = 0;
	}
	public Receiving recv = new Receiving();
	
	public class Recording {
		public bool enabled = false;
		public string	index_xml = "";
		public string	data_dir = "";
		public string	base_dir = "";
		public string?	open_dir = null;
		public int64	border_bytes = 512;
		public uint8[] buf;
		public MyAppProtocol.PacketRecorder? recorder = null;
		public MyContext.RecordStorage? storage = null;
		public int seeking_count = 0;
	}
	public Recording rec = new Recording();
	
	public Gee.Map<string, string> pack_to_legend;
	
	public TopContext(){
		this.pack_to_legend = new Gee.HashMap<string, string>();
	}
}

public errordomain TopError{
	CONFIG_ERROR,
	MISC_ERROR,
}

MyAppProtocol.MpTimelineReceiver<LiveChart.TimestampedValue?> mprecv_maker(int length){
	return new MyAppProtocol.MpTimelineReceiver<LiveChart.TimestampedValue?>(
		length, 
		LiveChart.Values.cmp,
		(ts, val) => {
			var ret = LiveChart.TimestampedValue();
			ret.timestamp = (double)ts;
			ret.value = val;
			return ret;
		},
		(tl) => {
			return (int64)tl.timestamp;
		}
	);
}

int main (string[] args) {
	
	// put the code of socket and file saving 
	//
	Gtk.init (ref args);
	
	var win = new MyApp.MainApp();
	var tog = new MyApp.PlotToggler();
	var ctx = new TopContext();
	
	tog.onBufferInitialize.connect(() => {
		print("reset my buffers on context\n");
		
		try{
			ctx.recv.channel?.shutdown(true);
		}catch{}
		ctx.recv.channel = null;
		
		try{
			ctx.recv.sock?.close();
		}catch{}
		ctx.recv.sock = null;
		
		if(ctx.recv.channel_task > 0){
			Source.remove(ctx.recv.channel_task);
			ctx.recv.channel_task = 0;
		}
		if(ctx.recv.emit_task > 0){
			Source.remove(ctx.recv.emit_task);
			ctx.recv.emit_task = 0;
		}
		ctx.recv.buf = new uint8[4096];
		ctx.recv.parser = mprecv_maker(ctx.recv.buf.length);
		
		ctx.rec.buf = new uint8[ctx.recv.buf.length * 2];
		ctx.rec.enabled = false;
		
		win.init_controller();
		win.clear_series();
		print("reset complete\n");
	});
	
	tog.onReceiverConfirmed.connect((protocol, port, rate_ms, src_dir, out err_str) => {
		if(port <= 0 || port > 0x0000FFFF){
			port = 8934;
		}
		if(rate_ms <= 0){
			rate_ms = 100;
		}
		try{
			bool only_play = false;
			ctx.rec.enabled = false;
			switch(protocol){
			case "udp":
				break;
			case "file":
				only_play = true;
				break;
			default:
				throw new TopError.CONFIG_ERROR("protocol must be \"udp\" or \"file\" currently.");
			}
			
			if(only_play){
				ctx.rec.enabled = true;
			}
			else{
				ctx.recv.sock = new Socket(SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);
				var addr = new InetAddress.any(SocketFamily.IPV4);
				var saddr = new InetSocketAddress(addr, (uint16)port);
				ctx.recv.sock.bind(saddr, true);
				
				//ctx.channel = new GLib.IOChannel.win32_socket(ctx.sock.get_fd());
				//ctx.recv.channel = new GLib.IOChannel.unix_new(ctx.recv.sock.get_fd());
				ctx.recv.channel = new GLib.IOChannel.win32_socket(ctx.recv.sock.get_fd());
				ctx.recv.channel.set_close_on_unref(true);
				ctx.recv.channel_task = ctx.recv.channel.add_watch(GLib.IOCondition.IN, (src, cond) => {
					
					SocketAddress raddr = null;
					var recved_len = ctx.recv.sock.receive_from(out raddr, ctx.recv.buf);
					int64 max_time = 0;
					//print("read from socket: %zd\n".printf(recved_len));
					
					if(recved_len > 0){
						ctx.recv.parser.push(ctx.recv.buf[0: recved_len], (parsed, ts) => {
							//print("parsed: %zd/ start: %lld\n".printf(parsed.length, ts));
							if(max_time < ts){
								max_time = ts;
							}
							var index_time = ctx.rec.recorder?.push(ts, parsed, parsed.length);
							ctx.rec.storage?.notify_index_recording(index_time);
						});
						win.set_max_time(max_time + rate_ms * 0);
					}
					return true;
				});
				
				ctx.recv.emit_task = Timeout.add(rate_ms, () => {
					//print("emit received dats\n");
					ctx.recv.parser.emit((name, serie) => {
						/*
						foreach(var v in serie){
							print("%s@%f->%f\n".printf(name, v.timestamp, v.value));
						}
						*/
						win.put_values(name, serie);
						//print("end\n");
						return true;
					}, rate_ms * 2);
					return true;
				});
			}
			ctx.rec.enabled = true;
		}
		catch(GLib.Error e){
			err_str = e.message;
		}
		return ctx.rec.enabled;
	});
	
	tog.onPrepareSerieReceive.connect((legend, pack_name, coeff) => {
		ctx.recv.parser.define_series(pack_name, coeff);
	});
	
	tog.onPrepareSerieCalculate.connect((legend, calc_name, coeff, method, priority) => {
		print("register calculate: %s/%s\n".printf(calc_name, method));
		if(!ctx.recv.parser.define_calc(calc_name, method, coeff, priority)){
			return false;
		}
		
		return true;
	});
	
	tog.onPrepareSeriePlot.connect((legend, name) => {
		ctx.pack_to_legend[name] = legend;
		win.register_serie(name);
		ctx.recv.parser.set_as_plottee(name, true);
	});
	
	tog.onAppendCalculateArg.connect((calc_name, arg_name, shift, legend) => {
		print("append arg to %s: %s/%f\n".printf(calc_name, arg_name, shift));
		ctx.recv.parser.put_calc_arg(calc_name, arg_name, shift);
	});
	
	tog.onAppendCalculateConst.connect((calc_name, const_name, const_value) => {
		print("append const to %s: %s/%s\n".printf(calc_name, const_name, const_value));
		ctx.recv.parser.put_calc_const(calc_name, const_name, const_value);
	});
	
	tog.onPresetSelected.connect((name) => {
		win.suspend_series();
	});
	
	tog.onVisibleChanged.connect((wentry) => {
		win.change_serie_appearance(wentry.pack, wentry.legend, wentry.grp, wentry.color, wentry.state);
	});
	
	tog.onLayoutSwitch.connect(() => {
		win.toggle_layout();
	});
	
	tog.onPrepareRecording.connect((base_dir, index_xml, data_dirname) => {
		//データ記録の準備。
		ctx.rec.base_dir = base_dir;
		ctx.rec.index_xml = index_xml;
		ctx.rec.data_dir = data_dirname;
		ctx.rec.border_bytes = 32 * 1024;
		print("record into [%s]\n".printf(ctx.rec.base_dir));
		print("data dir is [%s]\n".printf(ctx.rec.data_dir));
		//print("xml:\n%s\n".printf(ctx.rec.index_xml));
		win.init_controller(ctx.recv.sock == null);
	});
	
	tog.onInitError.connect((filename, msg) => {
		var dlg = new Gtk.MessageDialog(win.root, Gtk.DialogFlags.MODAL,
			Gtk.MessageType.WARNING, Gtk.ButtonsType.OK, msg);
		dlg.set_title(filename);
		dlg.run();
		dlg.destroy();
	});
	
	win.import_toggler(tog.root);
	win.root.show_all();
	win.root.destroy.connect(() => {
		tog.onBufferInitialize();
	});
	
	win.onRecordEnabled.connect((ref start_time) => {
		var time = new GLib.DateTime.now_local();
		bool newly_record = (ctx.recv.sock != null);
		int64 rtime = GLib.get_real_time() / 1000 % 1000;
		
		var curr_dir = newly_record ?
			"%s-from-%s.%03ds".printf(tog.basename, time.format("%Y%m%d-%Hh%Mm%S"), (int)rtime) : ".";
		
		var dst = GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S,
			ctx.rec.base_dir, curr_dir, ctx.rec.data_dir);
		var idx = GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S,
			ctx.rec.base_dir, curr_dir, "index.xml");
		
		ctx.rec.open_dir = GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S,
			tog.cwd, ctx.rec.base_dir, curr_dir);
		
		bool ret = false;
		File? file = null;
		
		if(!ctx.rec.enabled){
			return false;
		}
		
		try{
			print("on dir: %s\n".printf(dst));
			int64 first_time = 0;
			ctx.rec.recorder = new MyAppProtocol.PacketRecorder(dst, ctx.rec.border_bytes);
			ctx.rec.storage = new MyContext.RecordStorage(ctx.rec.recorder, ctx.recv.parser, 9188, 100);
			
			ctx.rec.storage.on_notifying_seekpoint.connect((out from_timestamp, out to_timestamp, out on_emit) => {
				if(win.get_current_plotrange(out from_timestamp, out to_timestamp)){
					ctx.rec.seeking_count++;
					if(ctx.rec.seeking_count < 5){
						return false;
					}
				}
				ctx.rec.seeking_count = 0;
				//print("notifying seek point from %lld to %lld\n".printf(from_timestamp, to_timestamp));
				MyAppProtocol.OnEmit<LiveChart.TimestampedValue?> func = (name, serie) => {
					if(serie.size <= 0){
						return true;
					}
					
					//print("%s: from %f to %f\n".printf(name, serie.first().timestamp, serie.last().timestamp));
					
					win.put_values(name, serie);
					//print("end\n");
					win.set_max_time((int64)(serie.last().timestamp));
					return true;
				};
				on_emit = func;
				return true;
			});
			
			ctx.rec.storage.on_request_release.connect((from_timestamp, to_timestamp) => {
				print("release %lld(%llX) to %lld(%llX)\n".printf(from_timestamp, from_timestamp, to_timestamp, to_timestamp));
				win.release_data(from_timestamp, to_timestamp);
			});
			
			win.release_data(-0x7FFFFFFFFFFFFFFF, (int64)start_time);
			
			if(ctx.rec.recorder.get_first_time(out first_time)){
				start_time = (double)first_time;
			}
			
			
			if(ctx.rec.recorder.get_last_time(out first_time)){
				win.set_max_time(first_time);
			}
			
			if(newly_record){
				print("make index: %s\n".printf(idx));
				file = GLib.File.new_for_path(idx);
				GLib.FileOutputStream os = file.create(FileCreateFlags.PRIVATE);
				os.write(ctx.rec.index_xml.data);
			}
			
			ret = true;
		}
		catch(GLib.Error e){
			print("Error: %s\n", e.message);
		}
		finally{
			if(file != null){
				file.unref();
			}
		}
		
		return ret;
	});
	
	win.onRecordDisabled.connect(() => {
		ctx.rec.recorder = null;
		ctx.rec.storage?.on_cancel();
		ctx.rec.storage = null;
		if(ctx.rec.open_dir != null){
			print(ctx.rec.open_dir);
			var file = File.new_for_path(ctx.rec.open_dir);
			if(file.query_exists()){
				bool r = false;
				try{
					r = GLib.AppInfo.launch_default_for_uri(file.get_uri(), null);
				}
				catch(GLib.Error e){}
				if(!r){
					Posix.system("explorer %s &".printf(ctx.rec.open_dir));
				}
			}
		}
	});
	
	win.root.destroy.connect(Gtk.main_quit);
	Gtk.main ();
	return 0;
}


