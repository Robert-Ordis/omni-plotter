namespace MyApp{
	public class ChartGridBox : GLib.Object {
		private struct Layout{
			public int x;
			public int y;
		}
		
		private static Layout[] LAYOUTS = {
			{1, 1},
			{1, 2},
			{2, 2},
			{2, 3}
		};
		
		private static double TICK_BASE = 80.0;
		
		private class ChartBox{
			public LiveChart.Config config	= new LiveChart.Config();
			public LiveChart.Chart chart;
			public LiveChart.Serie diff_serie;
			public LiveChart.PointReticle reticle;
			private double play_ratio;
			private int draw_rate;
			public ChartBox(){
				this.config.y_axis.unit = "";
				this.config.x_axis.tick_length = (float)TICK_BASE;
				this.config.x_axis.tick_interval = 1f;
				this.config.x_axis.lines.visible = true;
				this.config.movable_timeline = true;
				this.play_ratio = 1.0;
				this.draw_rate = 0;
				
				this.chart = new LiveChart.Chart(this.config);
				this.reticle = chart.new_point_reticle("");
				//this.root.add(this.chart);
				this.chart.refresh_every(this.draw_rate, this.play_ratio);
				this.chart.destroy.connect(() => {
					print("destroy chart\n");
				});
				var ds = new LiveChart.Serie("\"<CLR-DIFF>\"", new LiveChart.DiffStepLine());
				this.chart.add_serie(ds);
				this.diff_serie = ds;
				
				this.chart.on_chart_clicked.connect((device, x, y, btn) => {
					if(btn == 3){
						this.reticle.locked = !this.reticle.locked;
						this.reticle.aim_to_point(x, y, true);
					}
					else if(btn == 1){
						var tv = LiveChart.TimestampedValue();
						if(this.reticle.get_aimed_value(ref tv)){
							//1: find "younger equal" to "tv"
							var values = this.diff_serie.get_values().tail_set(tv);
							var tv_got = LiveChart.TimestampedValue();
							tv_got.timestamp = tv.timestamp;
							tv_got.value = double.NAN;
							
							if(values.size > 0){
								//2: if find, and if "same time", then remove it from diff once.
								var tv_tmp = values.first();
								if(tv_tmp.timestamp == tv.timestamp){
									values.remove(tv_tmp);
									tv_got = tv_tmp;
								}
							}
							
							if(tv.value != tv_got.value){
								//3: if "tv_got" is NAN or different, then plot clicked value newly.
								// -> Means, having different value, or newly clicked timestamp.
								this.diff_serie.add_with_timestamp(tv.value, (int64)tv.timestamp);
							}
						}
					}
					this.chart.queue_draw();
				});
				
				this.chart.on_chart_motioned.connect((device, x, y) => {
					this.reticle.aim_to_point(x, y, true);
					this.chart.queue_draw();
				});
				
				this.chart.on_legend_clicked.connect((device, serie, btn) => {
					if(this.reticle.target_serie == serie){
						this.reticle.target_serie = null;
					}
					else if(this.diff_serie == serie){
						serie.get_values().clear();
					}
					else{
						this.reticle.target_serie = serie;
					}
					this.chart.queue_draw();
				});
				
			}
			
			public void set_play_ratio(double play_ratio){
				this.play_ratio = play_ratio;
				this.chart.refresh_every(this.draw_rate, this.play_ratio);
			}
			
			public void set_draw_rate(int draw_rate){
				this.draw_rate = draw_rate;
				this.chart.refresh_every(this.draw_rate, this.play_ratio);
			}
			
			public void seek_to(int64 millis){
				this.config.time.current = millis;
			}
			
			public int64 get_current_timepoint(){
				return this.config.time.current;
			}
		}
		
		public Gtk.Grid root {get; private set;}
		private Gee.List<ChartBox> chart_boxes;
		private int layout_index = 1;
		private double play_ratio = 1.0;
		private int draw_rate = 0;
		private double tick_x_length = TICK_BASE;
		private int tick_x_interval_pow = 0;
		
		public signal void on_tick_changed(double shift_unit);
		
		public ChartGridBox(){
			this.root = new Gtk.Grid();
			//this.root.border_width = 2;
			this.root.row_homogeneous = true;
			this.root.column_homogeneous = true;
			
			this.chart_boxes = new Gee.ArrayList<ChartBox>();
			this.organize();
		}
		
		private void organize(){
			
			int i, j;
			int64 t = GLib.get_real_time() / 1000;
			Layout layout = LAYOUTS[this.layout_index];
			
			foreach(var cb in this.chart_boxes){
				cb.chart.refresh_every(-1);
				cb.chart.remove_all_series();
				this.root.remove(cb.chart);
				t = cb.get_current_timepoint();
			}
			this.chart_boxes.clear();

			j = layout.x * layout.y;
			
			for(i = 0; i < j; i++){
				var cb = new ChartBox();
				int x = i % layout.x;
				int y = i / layout.x;
				cb.set_play_ratio(this.play_ratio);
				cb.set_draw_rate(this.draw_rate);
				cb.seek_to(t);
				this.chart_boxes.add(cb);
				this.root.attach(cb.chart, x, y);
				
				cb.chart.on_chart_scrolled.connect((device, dx, dy) => {
					
					bool changed = true;
					this.tick_x_length += dy;
					if(this.tick_x_length < TICK_BASE){
						this.tick_x_length = TICK_BASE * 2;
						this.tick_x_interval_pow += 1;
					}
					else if(this.tick_x_length > (TICK_BASE * 2)){
						if(this.tick_x_interval_pow > -5){
							this.tick_x_interval_pow -= 1;
							this.tick_x_length = TICK_BASE;
						}
						else{
							this.tick_x_length = TICK_BASE * 2;
						}
					}
					else{
						changed = false;
					}
					
					var new_interval = GLib.Math.powf(2.0f, (float)this.tick_x_interval_pow);
					foreach(var bx in this. chart_boxes){
						bx.config.change_x_axis_tick((float)this.tick_x_length, new_interval);
						bx.chart.queue_draw();
					}
					
					if(changed){
						if(new_interval > 1.0f){
							new_interval = 1.0f;
						}
						this.on_tick_changed((double)new_interval * 1000.0);
					}
				});
				
				cb.config.change_x_axis_tick(
					(float)this.tick_x_length,
					GLib.Math.powf(2.0f, (float)this.tick_x_interval_pow)
				);
			}
			this.root.show_all();
		}
		
		public void switch_layout(int max_panels = 0){
			if(max_panels > 0){
				int i = 0;
				for(i = 0; i < LAYOUTS.length; i++){
					this.layout_index = (this.layout_index + 1) % LAYOUTS.length;
					var l = LAYOUTS[this.layout_index];
					if(max_panels >= (l.x * l.y)){
						break;
					}
				}
			}
			else{
				this.layout_index = (this.layout_index + 1) % LAYOUTS.length;
			}
			this.organize();
		}
		
		public void push_serie(int index, LiveChart.Serie serie){
			index = index % this.chart_boxes.size;
			print("push %s into %d-th\n".printf(serie.name, index));
			this.chart_boxes[index].chart.add_serie(serie);
			print("OK\n");
		}
		
		public void remove_serie(LiveChart.Serie serie){
			if(serie == null){
				return;
			}
			foreach(var cb in this.chart_boxes){
				var reticle = cb.reticle;
				cb.chart.remove_serie(serie);
				if(reticle.target_serie == serie){
					reticle.target_serie = null;
				}
			}
		}
		
		public void set_draw_rate(int ms){
			foreach(var cb in this.chart_boxes){
				cb.set_draw_rate(ms);
			}
			this.draw_rate = ms;
		}
		
		public void set_play_ratio(double play_ratio){
			foreach(var cb in this.chart_boxes){
				cb.set_play_ratio(play_ratio);
			}
			this.play_ratio = play_ratio;
		}
		
		public void refresh_now(){
			foreach(var cb in this.chart_boxes){
				cb.chart.queue_draw();
			}
		}
		
		public void seek_to(int64 unix_millis){
			foreach(var cb in this.chart_boxes){
				cb.seek_to(unix_millis);
			}
		}
		
		public int64 get_current_timepoint(){
			if(this.chart_boxes.size <= 0){
				return -1L;
			}
			return this.chart_boxes[0].get_current_timepoint();
		}
		
		public void clear_series(){
			foreach(var cb in this.chart_boxes){
				cb.chart.remove_all_series();
				cb.diff_serie.clear();
				cb.chart.add_serie(cb.diff_serie);
				cb.reticle.target_serie = null;
			}
		}
		
		public double get_time_range(){
			double time_width = 1000;
			if(this.chart_boxes.size > 0 && this.layout_index > 0){
				time_width = this.chart_boxes[0].config.time.head_offset;
			}
			
			if(this.layout_index > 0 && this.layout_index < LAYOUTS.length){
				Layout layout = LAYOUTS[this.layout_index];
				time_width *= layout.x;
			}
			return time_width;
		}
		
		public void erase_diff_plots(){
			foreach(var cb in this.chart_boxes){
				cb.diff_serie.clear();
			}
		}
		
	}
}
