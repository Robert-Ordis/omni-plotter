namespace MyAppProtocol.Calculation{
	
	//Parse number as "signed integer" forcibly.
	public class ToInt: Calculator{
		public const string method_name = "to-int";
		public override string get_method_name(){ return method_name; }
		
		
		private int bit_width = 8;
		
		private double compl_maker = 256;
		private double compl_border = 128;
		
		protected override bool set_const_value_(string name, string value){
			int tmp_val = bit_width;
			double dval = double.parse(value);
			if(name == "bit-width"){
				this.bit_width = (int)dval;
				int i;
				if(this.bit_width <= 1){
					this.bit_width = 8;
				}
				
				this.compl_maker = Math.pow(2, this.bit_width);
				this.compl_border = this.compl_maker / 2;
				return true;
			}
			return false;
		}
		
		protected override double calc_method(Gee.List<double?> arg_list){
			
			double ret = 0.0;
			
			if(arg_list.size <= 0){
				return ret;
			}
			
			ret = arg_list[0];
			
			while(ret >= this.compl_border){
				ret -= this.compl_maker;
			}
			
			while(ret < (0 - this.compl_border)){
				ret += this.compl_maker;
			}
			
			return ret;
		}
	}
}
