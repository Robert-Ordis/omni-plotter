namespace MyAppProtocol {
	
	/*
	string? recorder.push(tstamp, pkt, dir);
	*/
	
	public errordomain RecorderError{
		INIT,
	}
	
	//1 inst per 1 recording session.
	public class PacketRecorder {
		
		public delegate bool EachIndexExtracted(int64 first_time, string each_file, bool is_completed);
		
		private class RecordIndex{
			public int64 first_time;
			public int64 written_len;
			public string each_file;
			public bool is_completed;
			
			public RecordIndex(int64 first_time, string each_file, string base_dir){
				this.first_time = first_time;
				this.set_each_file(each_file, base_dir);
				this.written_len = 0L;
				this.is_completed = false;
			}
			public void set_each_file(string fpath, string base_dir){
				var path = GLib.Path.build_path(GLib.Path.DIR_SEPARATOR_S,
					base_dir, fpath);
				this.each_file = path;
			}
			
			public static int sorter(RecordIndex a, RecordIndex b){
				//print("%llX vs %llX\n".printf(a.first_time, b.first_time));
				int64 r = a.first_time - b.first_time;
				if(r > 0){
					return 1;
				}
				else if(r < 0){
					return -1;
				}
				return 0;
			}
			
		}
		
		private class Worker{
			private uint8[]	pkt = null;
			private int64	pkt_len = -1;
			private string dst;
			
			public Worker(string dst, uint8[] pkt, int64 pkt_len){
				if(pkt_len > 0 && pkt != null){
					this.pkt = new uint8[pkt_len];
					GLib.Memory.copy(this.pkt, pkt, (size_t)pkt_len);
					this.pkt_len = pkt_len;
				}
				this.dst = dst;
				//print("write %lld bytes into %s\n".printf(this.pkt_len, this.dst));
			}
			
			public void run() {
				//print("write %lld bytes into %s\n".printf(this.pkt_len, this.dst));
				if(this.pkt == null || this.pkt_len <= 0){
					return;
				}
				//Open file
				File file = File.new_for_path(this.dst);
				//Write pkt,
				try {
					FileOutputStream os = file.append_to(FileCreateFlags.NONE);
					os.write(this.pkt[0: this.pkt_len]);
				}
				catch(GLib.Error e){
					
				}
				//Close file.
			}
			
			
		}
		
		private static ThreadPool<Worker> pool = null;
		private Gee.SortedSet<RecordIndex> indexes;
		private RecordIndex index_searcher;
		private RecordIndex tail_searcher;
		
		private string base_dir;
		private int64 border_size;
		public int64 average_period {get; private set;}
		private bool _debug = false;
		
		//One inst per one recording session.
		public class PacketRecorder(string base_dir, int64 border_size) throws GLib.Error{
			
			//Thread pool will be One per Process (Not per PR-inst);
			if(pool == null){
				pool =  new ThreadPool<Worker>.with_owned_data((worker) => {
					worker.run();
				}, 1, false);
			}
			
			this.indexes = new Gee.TreeSet<RecordIndex>(RecordIndex.sorter);
			this.index_searcher = new RecordIndex(0, "sample.mpack", base_dir);
			this.tail_searcher = new RecordIndex(0, "tail.mpack", base_dir);
			this.base_dir = base_dir;
			this.border_size = border_size;
			
			if(GLib.DirUtils.create_with_parents(this.base_dir, 0666) < 0){
				int e = GLib.errno;
				throw new RecorderError.INIT("err: %d/%s".printf(e, GLib.strerror(e)));
			}
			this.average_period = 0;
			this.setup_index();
		}
		
		private void setup_index(){
			var app_dir = GLib.File.new_for_path(this.base_dir);
			try{
				var cancellable = new GLib.Cancellable();
				GLib.FileEnumerator enumerator = app_dir.enumerate_children(
					GLib.FileAttribute.STANDARD_DISPLAY_NAME,
					GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS
				);
				
				FileInfo? file_info = null;
				while(
					!cancellable.is_cancelled() &&
					((file_info = enumerator.next_file(cancellable)) != null)
				){
					var fname = file_info.get_display_name();
					int64 tstamp = -1;
					print("%s->%s/%lld\n".printf(fname, GLib.FileUtils.test(fname, GLib.FileTest.IS_DIR).to_string(), file_info.get_size()));
					
					if(file_info.get_file_type() == GLib.FileType.DIRECTORY){continue;}
					
					if(fname.scanf("%llX.mpack", &tstamp) > 0){
						
						var index = new RecordIndex(tstamp, fname, this.base_dir);
						index.written_len = file_info.get_size();
						index.is_completed = true;
						//print("%s->OK, this is one of the record->%lld\n".printf(index.each_file, index.first_time));
						this.indexes.add(index);
						
					}
				}
				if(this.indexes.size > 0){
					this.average_period = (this.indexes.last().first_time - this.indexes.first().first_time) / this.indexes.size;
				}
			}
			catch(GLib.Error err){
				
			}
		}
		
		public void each_indexes_ranged(int64 from_ts, int64 to_ts, EachIndexExtracted func){
			var head_index = this.index_searcher;
			var tail_index = this.tail_searcher;
			Gee.SortedSet<RecordIndex>? subset = null;
			if(from_ts > to_ts || this.indexes.size <= 0){
				return;
			}
			
			//1: get subset
			head_index.first_time = from_ts - this.average_period * 2;
			tail_index.first_time = to_ts + 1 + this.average_period * 2;
			/*
			print("search[%llX -> %llX] from %d indexes\n".printf(
				head_index.first_time, tail_index.first_time, 
				this.indexes.size));
			print("ave: %llx\n".printf(this.average_period));
			*/
			if(this.indexes.first().first_time < head_index.first_time && this.indexes.last().first_time >= tail_index.first_time){
				subset = this.indexes.sub_set(head_index, tail_index);
			}
			else if(this.indexes.first().first_time >= head_index.first_time){
				subset = this.indexes.head_set(tail_index);
			}
			else if(this.indexes.last().first_time < tail_index.first_time){
				subset = this.indexes.tail_set(head_index);
			}
			else {
				subset = this.indexes;
			}
			//print("subset: %d elems\n".printf(subset.size));
			foreach(var idx in subset){
				//call function(int64 index, string filepath);
				if(!func(idx.first_time, idx.each_file, idx.is_completed)){
					break;
				}
			}
			
			return;
		}
		
		/// \todo Define the "final time". If the size exceeds the limit but tstamp is older than "final time", then put pkt into older area.
		public int64 push(int64 tstamp, uint8[] pkt, int64 pkt_len){
			//1: search tstamp.
			var fname = "%016llX.mpack".printf(tstamp);
			var tmp_index = this.index_searcher;
			tmp_index.set_each_file(fname, this.base_dir);
			
			if(this.indexes.size <= 0){
				// new session.
				tmp_index = null;
			}
			else if(this.indexes.last().first_time >= tstamp){
				// highest >= tstamp: push into ceil(geq).
				//print("highest >= tstamp: push into ceil(geq).\n");
				tmp_index = this.indexes.ceil(tmp_index);
			}
			else{
				// highest < tstamp: push into last MAYBE.
				//print("highest < tstamp: push into last MAYBE.\n");
				tmp_index = this.indexes.last();
				if(this.border_size < tmp_index.written_len){
					//reached to size limit->new index.
					this.average_period += (tstamp - tmp_index.first_time);
					if(this.indexes.size > 2){
						this.average_period /= 2;
					}
					tmp_index.is_completed = true;
					tmp_index = null;
				}
			}
			
			if(tmp_index == null){
				tmp_index = new RecordIndex(tstamp, fname, this.base_dir);
				this.indexes.add(tmp_index);
			}
			
			tmp_index.written_len += pkt_len;
			//print("border size is %lld\n".printf(this.border_size));
			/*
			foreach(var v in this.indexes){
				print("%lld->%s(%lld bytes)\n".printf(v.first_time, v.each_file, v.written_len));
			}
			*/
			
			//then push into thread pool.
			pool.add(new Worker(tmp_index.each_file, pkt, pkt_len));
			//print("waiting = %u\n".printf(pool.unprocessed()));
			
			return tmp_index.first_time;
		}
		
		public bool get_first_time(out int64 ret){
			if(this.indexes.size > 0){
				ret = this.indexes.first().first_time;
				return true;
			}
			return false;
		}
		
		public bool get_last_time(out int64 ret){
			if(this.indexes.size > 0){
				ret = this.indexes.last().first_time;
				return true;
			}
			return false;
		}
		
	}
}