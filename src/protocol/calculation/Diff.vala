namespace MyAppProtocol.Calculation{
	
	public class Diff: Calculator{
		public const string method_name = "diff";
		public override string get_method_name(){ return method_name; }
		
		Gee.List<int64?> timepoints = new Gee.ArrayList<int64?>();
		Gee.List<double?> values = new Gee.ArrayList<double?>();
		
		static int limit_size = 3;
		
		public override void set_current_timepoint(int64 timepoint){
			this.timepoints.add(timepoint);
			//print("diff: timepoint is %f -> %f\n".printf(this.prev_timepoint, this.curr_timepoint));
		}
		
		
		
		protected override double calc_method(Gee.List<double?> arg_list){
			
			double ret = double.NAN;
			double val = 0.0;
			double time_diff = 0.0;
			
			if(arg_list.size <= 0){
				return 0.0;
			}
			
			this.values.add(arg_list[0]);
			
			while(this.values.size >= limit_size + 1){
				this.values.remove_at(0);
			}
			
			while(this.timepoints.size >= limit_size + 1){
				this.timepoints.remove_at(0);
			}
			
			if(this.values.size < limit_size || this.timepoints.size < limit_size){
				return 0.0;
			}
			if((time_diff = (double)(this.timepoints.last() - this.timepoints[0])) == 0.0){
				return 0.0;
			}
			
			val = 0.0;
			val -= this.values[0];
//			val += 8*this.values[1];
//			val -= 8*this.values[2];
			val += this.values.last();
			
			//ret = (val - this.prev_val) / (time_diff);
			ret = val / time_diff;
			
			return ret;
		}
	}
}
