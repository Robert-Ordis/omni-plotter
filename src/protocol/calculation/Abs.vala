namespace MyAppProtocol.Calculation{
	
	public class Abs: Calculator{
		public const string method_name = "abs";
		public override string get_method_name(){ return method_name; }
		
		protected override double calc_method(Gee.List<double?> arg_list){
			
			double ret = 0.0;
			
			switch(arg_list.size){
			case 0:
				break;
			case 1:
				return arg_list[0].abs();
			default:
				break;
			}
			foreach(var v in arg_list){
				ret = ret + (v * v);
			}
			return GLib.Math.sqrt(ret);
		}
	}
}
