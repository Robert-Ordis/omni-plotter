namespace MyAppProtocol.Calculation{
	
	public class Sum: Calculator{
		public const string method_name = "sum";
		public override string get_method_name(){ return method_name; }
		
		protected override double calc_method(Gee.List<double?> arg_list){
			
			double ret = 0.0;
			
			foreach(var v in arg_list){
				ret = ret + v;
			}
			return ret;
		}
	}
}
