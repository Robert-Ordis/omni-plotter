namespace MyAppProtocol.Calculation{
	
	
	public delegate double ArgPicker(string name);
	
	public abstract class Calculator {
		struct Argument {
			public string name;
			public double shift;
			//public double coeff = 1.0;
		}
		
		public static int sorter(Calculator a, Calculator b){
			return a.priority - b.priority;
		}
		
		public int priority = 0;
		public string name = "";
		
		private Gee.List<Argument?> args = new Gee.ArrayList<Argument?>();
		private Gee.List<double?> calc_args = new Gee.ArrayList<double?>();
		private Gee.Map<string, string> const_map = new Gee.HashMap<string, string>();
		
		public virtual void set_current_timepoint(int64 timepoint){}
		
		//固定値の宣言。派生先クラスに承認された場合にtrue。
		public void set_const_value(string name, string value){
			if(this.set_const_value_(name, value)){
				this.const_map[name] = value;
			}
		}
		protected virtual bool set_const_value_(string name, string value){return false;}
		
		//実際の計算
		protected abstract double calc_method(Gee.List<double?> arg_list);
		
		public abstract string get_method_name();
		
		//呼んだら、渡されたラムダ式を以って外から値を持っていく。
		//その際、ラムダ式はname(=外で定義した変数名)を引数として起動される。
		public double calculate(ArgPicker arg_picker){
			this.calc_args.clear();
			foreach(var v in this.args){
				this.calc_args.add(arg_picker(v.name) + v.shift);
			}
			return this.calc_method(this.calc_args);
		}
		
		//引数を登録する。
		public void register_arg(string name, double shift){
			var arg= Argument();
			arg.name = name;
			arg.shift = shift;
			this.args.add(arg);
		}
		
		public void clear(){
			this.args.clear();
		}
		
		public static Calculator? new_by_name(string name){
			switch(name){
			case Abs.method_name:
				return new Abs();
			case Atan2.method_name:
			case "atan":
			case "angle":
				return new Atan2();
			/// \note "diff"は現在、扱いづらいので放置
/*
			case Diff.method_name:
				return new Diff();
*/
			case ToInt.method_name:
				return new ToInt();
			case Sum.method_name:
				return new Sum();
			default:
				return null;
			}
		}
		
		public Calculator copy(){
			var ret = Calculator.new_by_name(this.get_method_name());
			//宣言された変数群をコピーする
			foreach(var arg in this.args){
				ret.args.add(arg);
			}
			//宣言された定数群をコピーする
			foreach(var e in this.const_map){
				ret.set_const_value(e.key, e.value);
			}
			ret.priority = this.priority;
			ret.name = this.name;
			return ret;
		}
		
	}
	
}