using GLib;

namespace MyAppProtocol{
	
	
	/// \note	原案ではSocketAddressも使う予定だったが、比較の仕方に確信が取れないのと複雑になるので没。
	///			発信元の特定についてはソケットにコネクトさせればひとまず事足りるのでそれでやる。
	///			そもそもの話、建前上はTCPバッファも同じく扱うことを想定しているのでsaddrは排除しないといけない。
	public delegate bool OnEmit<T>(string name, Gee.SortedSet<T> serie);
	
	public delegate T TimelineMaker<T, V>(int64 timestamp, V value);
	
	public delegate int64 TimestampGetter<T>(T timeline);
	
	// V->派生先のクラスにてどの値で読むのか決定する
	public interface Receiver<T, V>: GLib.Object {
		
		//パケットを詰め込む。パースエラーを起こさないシロモノならtrue。
		//理想的には、parsedに「この時点をもって正しくパースできたバイナリ」が入る。
		//返はparsedに入れられたバイト数。駄目ならマイナス。
		public abstract ssize_t push(uint8[] packet, ref uint8[] parsed, out int64 start_time);
		
		//時系列を一つ登録する。それ以外は読み捨てることを実装者は約束する。
		public abstract bool define_series(string name, double coeff);
		
		//OnEmitで指定された関数を呼び出す。
		public abstract void emit(OnEmit<T>? on_emit, int64 threshold_ms = -1);
		
		//OnEmitで指定された関数をもって、現在ため込んでいる値を呼び出す。
		public abstract void refer_ranged(OnEmit<T>? on_emit, int64 start, int64 end);
		
		//計算系列を一つ定義する
		//methodはおおむね…、abs, atan2ぐらいじゃね？
		public abstract bool define_calc(string calc_name, string method, double coeff, int priority);
		
		//計算系列に対してarg_nameを引数にする。
		public abstract bool put_calc_arg(string calc_name, string arg_name, double shift);
		
		//計算系列に対して、固定数を定義する
		public abstract bool put_calc_const(string calc_name, string const_name, string const_value);
		
		//プロット対象として宣言する
		public abstract bool set_as_plottee(string name, bool for_plot);
		
		
	}
}
