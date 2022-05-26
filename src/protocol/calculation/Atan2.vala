namespace MyAppProtocol.Calculation{
	
	public class Atan2: Calculator{
		public const string method_name = "atan2";
		public override string get_method_name(){ return method_name; }
		
		protected override double calc_method(Gee.List<double?> arg_list){
			
			switch(arg_list.size){
			case 0:
				return 0.0;
			case 1:
				return 0.0;
			default:
				break;
			}
			
			return GLib.Math.atan2(arg_list[0], arg_list[1]);
		}
	}
}
