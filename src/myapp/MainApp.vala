namespace MyApp{
	public class MainApp: GLib.Object{
		private class ChildWidgets {
			public Gtk.ToggleButton play_pause {get; private set;}
			public Gtk.ToggleButton record {get; private set;}
			public Gtk.Adjustment play_time {get; private set;}
			public Gtk.Scale seek_bar {get; private set;}
			public Gtk.Box plotter_box {get; private set;}
			public Gtk.Box toggler_box {get; private set;}
			public ChildWidgets(Gtk.Builder builder){
				this.play_pause = builder.get_object("play_pause") as Gtk.ToggleButton;
				this.record = builder.get_object("record") as Gtk.ToggleButton;
				this.play_time = builder.get_object("play_time") as Gtk.Adjustment;
				this.seek_bar = builder.get_object("seek_bar") as Gtk.Scale;
				this.plotter_box = builder.get_object("plotter_box") as Gtk.Box;
				this.toggler_box = builder.get_object("toggler_box") as Gtk.Box;
			}
		}
		
		public Gtk.Window root {get; private set;}
		private ChildWidgets ui;
		
		private class SerieBox {
			public int grp_num = -1;
			public LiveChart.Serie serie = null;
		}
		private Gee.Map<string, SerieBox> serie_map;
		
		private ChartGridBox grid_box;
		
		private int64 prev_time;
		private uint timer = 0;
		private bool is_seek_changing = false;
		
		public signal void onSeeked(int64 timepoint_ms);
		public signal bool onRecordEnabled(ref double start_time);
		public signal void onRecordDisabled();
		
		public MainApp(string res = "/resource/ui/main.ui"){
			var builder = new Gtk.Builder.from_resource(res);
			this.root = builder.get_object("main") as Gtk.Window;
			this.root.set_default_size(800, 350);
			this.ui = new ChildWidgets(builder);
			
			this.serie_map = new Gee.HashMap<string, SerieBox>();
			this.grid_box = new ChartGridBox();
			
			
			this.ui.play_pause.toggled.connect(() => {
				//true->play
				//false->pause
				if(this.ui.play_pause.active && !this.ui.record.active){
					this.grid_box.set_play_ratio(1.0);
				}
				else{
					this.grid_box.set_play_ratio(0.0);
				}
			});
			
			this.ui.record.toggled.connect(() => {
				this.ui.seek_bar.set_sensitive(this.ui.record.active);
				if(this.ui.record.active){
					double start_time = (double)this.grid_box.get_current_timepoint();
					if(!this.onRecordEnabled(ref start_time)){
						//If failed->set as false.
						this.ui.record.active = false;
						this.ui.record.toggled();
						return;
					}
					this.ui.play_time.lower = start_time;
				}
				else{
					this.onRecordDisabled();
				}
				this.ui.play_pause.toggled();
			});
			this.ui.play_time.set_page_increment(60.0 * 1000.0);
			this.ui.play_time.set_step_increment(1000.0);
			this.ui.play_time.value_changed.connect(() => {
				this.grid_box.seek_to((int64) this.ui.play_time.value);
				this.grid_box.refresh_now();
			});
			this.grid_box.on_tick_changed.connect((step) => {
				this.ui.play_time.set_step_increment(step);
			});
			
			this.ui.seek_bar.format_value.connect((val) => {
				int64 t = (int64) val;
				var time = new DateTime.from_unix_utc(t / 1000).to_local();
				
				return "%s.%03lld".printf(time.format("%y-%m-%d %R:%S"), t % 1000L);
			});
			
			this.ui.seek_bar.button_press_event.connect((event) => {
				this.is_seek_changing = true;
				return false;
			});
			
			this.ui.seek_bar.button_release_event.connect((event) => {
				this.is_seek_changing = false;
				return false;
			});
			
			//this.ui.seek_bar.set_increments(1.0, 10.0);
			
			this.ui.plotter_box.pack_start(this.grid_box.root, true, true, 0);
			
			this.prev_time = GLib.get_monotonic_time() / 1000;
			this.timer = GLib.Timeout.add(33, () => {
				int64 curr_time = GLib.get_monotonic_time() / 1000;
				//if(this.root.is_active){
					if(this.ui.play_pause.active){
						//Record mode & playing mode
						var next = this.ui.play_time.value + (double)(curr_time - this.prev_time);
						if(!this.is_only_play() && next > this.ui.play_time.upper){
							this.ui.play_time.upper = next;
							this.ui.seek_bar.set_fill_level(this.ui.play_time.upper - this.ui.play_time.lower);
						}
						
						this.ui.play_time.value = next;
						if(!this.ui.record.active){
							this.ui.play_time.lower = next;
						}
					}
					this.prev_time = curr_time;
				//}
				return true;
			});
			
			this.root.destroy.connect(() => {
				if(this.timer > 0){
					GLib.Source.remove(this.timer);
				}
			});
			//this.root.set_keep_above(true);
			this.grid_box.set_draw_rate(0);
			this.init_controller();
		}
		
		public void init_controller(bool only_play = false){
			this.ui.play_time.lower = 0.0f;
			this.ui.play_time.value = 0.0f;
			this.ui.play_time.upper = 0.0f;
			
			this.ui.record.active = only_play;
			this.ui.record.set_sensitive(!only_play);
			this.ui.play_pause.active = true;
			this.ui.play_pause.toggled();
		}
		
		private bool is_only_play(){
			return !this.ui.record.sensitive;
		}
		
		public void set_max_time(int64 millis){
			//print("step: %f\n".printf(this.ui.play_time.step_increment));
			double v = (double)millis;
			if(!this.ui.record.active){
				this.ui.play_time.lower = this.ui.play_time.upper;
			}
			if(this.ui.play_time.upper < v){
				this.ui.play_time.upper = v;
			}
			this.ui.seek_bar.set_fill_level(this.ui.play_time.upper - this.ui.play_time.lower);
			if(!this.ui.record.active && this.ui.play_pause.active){
				this.ui.play_time.value = this.ui.play_time.upper;
			}
		}
		
		public void import_toggler(Gtk.Widget ui){
			this.ui.toggler_box.add(ui);
		}
		
		public void clear_series(){
			this.grid_box.clear_series();
			this.serie_map.clear();
		}
		
		public void toggle_layout(){
			//1: remove All series from chart. or delete all "chart" widgets.
			//2: restruct the chart panel grid.
			//3: register all series to chart panel grid again.
			int max_grp = 0;
			foreach(var entry in this.serie_map){
				var sb = entry.value;
				if(max_grp < sb.grp_num){
					max_grp = sb.grp_num;
				}
			}
			
			//this.grid_box.switch_layout(max_grp + 1);
			this.grid_box.switch_layout();
			foreach(var entry in this.serie_map){
				var sb = entry.value;
				if(sb.grp_num < 0 || sb.serie == null){
					continue;
				}
				
				this.grid_box.push_serie(sb.grp_num, sb.serie);
			}
		}
		
		public void register_serie(string index_name){
			//1: make new instance of SerieBox;
			//2: grp = -1
			SerieBox? sb = this.serie_map.get(index_name);
			if(sb == null){
				sb = new SerieBox();
			}
			else if(sb.serie != null){
				this.grid_box.remove_serie(sb.serie);
			}
			
			sb.serie = new LiveChart.Serie("", new LiveChart.LineArea(new LiveChart.Values(-1)));
			
			this.serie_map[index_name] = sb;
		}
		
		public void change_serie_appearance(string index_name, string legend, int grp, string color_code, bool visible){
			
			//1: check if the serie(from index_name) does exist.
			var sb = this.serie_map.get(index_name);
			if(sb == null){
				return;
			}
			
			//2: if existing, remove it from chart panel grid at once
			this.grid_box.remove_serie(sb.serie);
			
			//3: configure serie again.
			sb.serie.name = legend;
			sb.grp_num = grp;
			sb.serie.visible = visible;

			//print("%s: parse color:%s\n".printf(index_name, col_code));
			bool res;
			Gdk.RGBA col = {};
			RGBAUtils.parse(ref col, color_code);
			
			sb.serie.line.color = col;
			
			//4: put the serie into chart grid panel again.
			if(grp >= 0){
				this.grid_box.push_serie(grp, sb.serie);
			}
			
		}
		
		public void put_values(string index_name, Gee.SortedSet<LiveChart.TimestampedValue?> new_points){
			var sb = this.serie_map.get(index_name);
			if(sb == null || sb.serie == null || sb.grp_num < 0 || new_points.size <= 0){
				return;
			}
			/*
			foreach(var point in new_points){
				//print("%s: %f@%lld\n".printf(index_name, point.data, point.timepoint));
				sb.serie.add_with_timestamp(point.data, point.timepoint);
			}
			*/
			//print("[%s]->pushing %d values\n".printf(index_name, new_points.size));
			sb.serie.add_all(new_points);
			if(!this.ui.record.active){
				var end = LiveChart.TimestampedValue();
				end.timestamp = new_points.first().timestamp - this.grid_box.get_time_range();
				//print("release on unrecorded %d -> ".printf(sb.serie.get_values().size));
				sb.serie.get_values().head_set(end).clear();
				//print("%d\n".printf(sb.serie.get_values().size));
				
			}
			
			if(!this.ui.play_pause.active){
				this.grid_box.refresh_now();
			}
			
		}
		
		public void suspend_series(){
			this.grid_box.clear_series();
			foreach(var entry in this.serie_map){
				entry.value.grp_num = -1;
			}
		}
		
		public bool get_current_plotrange(out int64 from_timestamp, out int64 to_timestamp){
			//return this.ui.play_time.value;
			to_timestamp = (int64)this.ui.play_time.value;
			from_timestamp = to_timestamp - (int64)(this.grid_box.get_time_range());
			return this.is_seek_changing;
		}
		
		public void release_data(int64 from_timestamp, int64 to_timestamp){
			var start = LiveChart.TimestampedValue();
			var end= LiveChart.TimestampedValue();
			start.timestamp = (double)from_timestamp;
			end.timestamp = (double)to_timestamp;
			//print("release %f -> %f data\n".printf(start.timestamp, end.timestamp));
			foreach(var sb in this.serie_map.values){
				var s = sb.serie.get_values();
				if(s.size <= 0){
					continue;
				}
				//print("%f -> %f having\n".printf(s.first().timestamp, s.last().timestamp));
				//print("%f -> %f delete\n".printf(start.timestamp, end.timestamp));
				
				//print("release... %d -> ".printf(s.size));
				if(start.timestamp < s.first().timestamp){
					s.head_set(end).clear();
				}
				else{
					s.sub_set(start, end).clear();
				}
				//print("%d\n".printf(s.size));
			}
		}
	}
}
