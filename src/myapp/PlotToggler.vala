namespace MyApp{
	
	public class PlotToggler: GLib.Object{
		private class NAME{
			public const string PLOTTER = "plotter";
			public const string EXPORTER = "exporter";

			public const string RECEIVER = "receiver";
			public const string LOCAL = "local";
			public const string DEST = "dest";
			
			public const string PORT = "port";
			public const string PROTOCOL = "protocol";
			public const string RATE_MS = "rate_ms";
			public const string DIR = "dir";
			
			public const string MAPPING = "mapping";
			public const string CALCULATE = "calculate";
			
			public const string METHOD = "method";
			public const string PRIORITY = "priority";
			
			public const string NAME = "name";
			public const string PACK = "pack";
			public const string COEFF = "coeff";
			public const string GROUP = "group";
			public const string LEGEND = "legend";
			public const string COLOR = "color";
			public const string FOR_PLOT = "for-plot";
			
			public const string ARG = "arg";
			public const string SHIFT = "shift";
			
			public const string CONST = "const";
			public const string VALUE = "value";
			
			public const string LAYOUT = "layout";
			public const string SERIE = "serie";
			public const string SRC = "src";
			
			public const string SHOW_ALL = "<SHOWING ALL>";
			
		}
		
		public class SeriesStorage {
			
			public class Entry{
				public int grp;
				public string legend;
				public string pack;
				public string color;
				public bool state;
			}
			
			//default list of series in one layouts.
			public Gee.TreeSet<Entry> layout_default {get; private set;}
			
			//string->list of series in one layouts
			public Gee.Map<string, Gee.TreeSet<Entry>> layouts {get; private set;}
			
			public SeriesStorage(){
				CompareDataFunc<Entry> cmp = (a, b) => {
					int r = a.grp - b.grp;
					if(r != 0){
						return r;
					}
					return GLib.strcmp(a.legend, b.legend);
				};
				this.layout_default = new Gee.TreeSet<Entry>(cmp);
				this.layouts = new Gee.HashMap<string, Gee.TreeSet<Entry>>();
			}
			
			public void add_entry(string? layout_name, Entry wentry){
				var tmp = this.layout_default;
				if(layout_name != null){
					if((tmp = this.layouts[layout_name]) == null){
						this.layouts[layout_name] = new Gee.TreeSet<Entry>(this.layout_default.compare_func);
						tmp = this.layouts[layout_name];
					}
				}
				tmp.add(wentry);
			}
			
			public void clear(){
				
				this.layout_default.clear();
				
				foreach(var entry in this.layouts){
					
					entry.value.clear();
				}
				this.layouts.clear();
			}
			
		}
		
		
		private class ChildWidgets {
			public Gtk.ComboBox presets {get; private set;}
			public Gtk.ListBox series_list {get; private set;}
			public Gtk.Button layout_switch {get; private set;}
			//public Gtk.FileChooserButton file_chooser {get;  set;}
			public Gtk.FileChooserNative file_chooser {get; private set;}
			public string file_button_str {get; private set;}
			public Gtk.Button file_button {get; private set;}
			public ChildWidgets(Gtk.Builder builder){
				
				this.presets = builder.get_object("presets") as Gtk.ComboBox;
				var txt = new Gtk.CellRendererText();
				this.presets.pack_start(txt, true);
				this.presets.add_attribute(txt, "text", 0);
				
				this.series_list = builder.get_object("series_list") as Gtk.ListBox;
				
				this.layout_switch = builder.get_object("layout_switch") as Gtk.Button;
				
				this.file_button = builder.get_object("file_button") as Gtk.Button;
				this.file_button_str = this.file_button.label;
				//this.file_chooser = builder.get_object("file_chooser") as Gtk.FileChooserButton;
				this.file_chooser = builder.get_object("file_chooser") as Gtk.FileChooserNative;
			}
		}
		

		public Gtk.Widget root {get; private set;}
		private ChildWidgets ui;
		private SeriesStorage dui;
		
		public string cwd {get; private set;}
		
		public string basename { get; private set; default = "";}
		public signal void onInitError(string filename, string msg);
		public signal void onBufferInitialize();
		public signal bool onReceiverConfirmed(string protocol, int port, int rate_ms, string? src_dir, out string err_str);
		public signal void onPrepareSerieReceive(string legend, string pack_name, double coeff);
		public signal bool onPrepareSerieCalculate(string legend, string calc_name, double coeff, string method, int priority);
		public signal void onPrepareSeriePlot(string legend, string pack_name);
		public signal void onAppendCalculateArg(string calc_name, string arg_name, double shift, string legend);
		public signal void onAppendCalculateConst(string calc_name, string const_name, string const_value);
		
		public signal void onPresetSelected(string? name);
		public signal void onVisibleChanged(SeriesStorage.Entry wentry);
		
		public signal void onPrepareRecording(string base_dir, string xml_dump, string data_dirname);
		
		
		public signal void onLayoutSwitch();
		//import to series_list
		
		public PlotToggler(string res = "/resource/ui/toggler.ui"){
			var builder = new Gtk.Builder.from_resource(res);
			this.root = builder.get_object("main") as Gtk.Widget;
			this.root.unparent();
			this.ui = new ChildWidgets(builder);
			this.dui = new SeriesStorage();
			
			//this.ui.file_chooser.file_set.connect();
			
			this.ui.file_button.clicked.connect(() => {
				switch(this.ui.file_chooser.run()){
				case Gtk.ResponseType.ACCEPT:
					print("accept: %s\n".printf(this.ui.file_chooser.get_filename()));
					this.onFileSelected();
					print("basename is %s\n".printf(this.basename));
					if(this.basename == ""){
						this.ui.file_button.label = this.ui.file_button_str;
					}
					else{
						this.ui.file_button.label = this.basename;
					}
					break;
				}
			});
			
			this.onBufferInitialize.connect(() => {
				
				//refresh "presets"
				this.ui.presets.set_model(null);
				
				//refresh current "series_list"
				this.ui.series_list.foreach((elem) => {this.ui.series_list.remove(elem);});
				
				//refresh dynamic widgets storage.
				this.dui.clear();
				
			});
			
			this.ui.presets.changed.connect(()=>{
				Gtk.TreeIter iter;
				GLib.Value  val;
				var model = this.ui.presets.get_model();
				
				if(model != null){
					this.ui.presets.get_active_iter(out iter);
					model.get_value(iter, 0, out val);
					this.onPresetSelected((string)val);
					this.changePreset((string)val);
				}
				else{
					this.onPresetSelected(null);
					this.changePreset(null);
				}
			});
			
			this.ui.layout_switch.clicked.connect(() => {
				this.onLayoutSwitch();
			});
			
			this.onInitError.connect((fname, msg) => {
				this.basename = "";
				print("%s: %s\n".printf(fname, msg));
			});
			
		}
		
		private void onFileSelected(){
			Xml.Doc *doc = null;
			Xml.Doc *out_doc = null;
			string filename = this.ui.file_chooser.get_filename();
			string rec_dir = null;
			this.basename = GLib.Path.get_basename(filename);
			print("read %s\n".printf(filename));
			print("->%s\n".printf(this.basename));
			this.cwd = GLib.Path.get_dirname(filename);
			print("cwd = %s\n".printf(this.cwd));
			GLib.Environment.set_current_dir(this.cwd);
			
			try{
				Xml.Node *node = null;
				this.onBufferInitialize();
				
				if((doc = Xml.Parser.parse_file(filename)) == null){
					int err = GLib.errno;
					if(err != 0){
						throw IOError.from_errno(err);
					}
					throw new XmlUtils.ReadError.PARSE_ERROR("May not be xml");
				}
				
				// Watching "plotter" element(root).
				if((node = doc->get_root_element()) == null){
					throw new XmlUtils.ReadError.PARSE_ERROR("May be not xml.");
				}
				if(node->name != NAME.PLOTTER){
					throw new XmlUtils.ReadError.CONTENT_ERROR("Root name must be \"%s\"".printf(NAME.PLOTTER));
				}
				
				// Watching "receiver" element. even if null;
				{
					XmlUtils.search_named_children(node, NAME.RECEIVER, (node) => {
						this.readReceiver(node, out rec_dir);
						return false;
					}, true);
				}
				// Watching "mapping" elements
				var overrideMap = new Gee.HashMap<string, SeriesStorage.Entry>();
				{
					XmlUtils.search_named_children(node, NAME.MAPPING, (node) => {
						
						//"name"->fundamental value.
						string name = XmlUtils.parse_prop<string>(node, NAME.NAME, true, XmlUtils.get_str);
						
						//"pack"->If this val is written, override this from value written as "name".
						string pack = XmlUtils.parse_prop<string>(node, NAME.PACK, false, XmlUtils.get_str, name);
						
						//"coeff"->Multiply the received value.
						double coeff = XmlUtils.parse_prop<double?>(node, NAME.COEFF, false, XmlUtils.parse_double, 1.0);
						
						//"group"->Which panel is destination to plot this serie?
						int def_grp = XmlUtils.parse_prop<int>(node, NAME.GROUP, false, XmlUtils.parse_int, 0);
						
						//"legend"->legend. if empty, same as "name".
						string legend = XmlUtils.parse_prop<string>(node, NAME.LEGEND, false, XmlUtils.get_str, pack);
						
						//"color"->color code
						string color = XmlUtils.parse_prop<string>(node, NAME.COLOR, false, XmlUtils.get_str, "#ffffff");
						
						//"for-plot"->if "false", then only for calculating but not for plotting.
						bool for_plot = bool.parse(XmlUtils.parse_prop<string>(node, NAME.FOR_PLOT, false, XmlUtils.get_str, "true"));
						
						var wentry = this.makeSerieButton(null, legend, pack, color, def_grp);
						
						// notify user to "prepare for receive and showing pack with name "legend".";
						this.onPrepareSerieReceive(legend, pack, coeff);
						if(for_plot){
							this.onPrepareSeriePlot(legend, pack);
						}
						else{
							wentry.grp = -1;
						}
						
						if(wentry.grp >= 0){
							this.dui.add_entry(null, wentry);
						}
						overrideMap[name] = wentry;
						
						return true;
					});
				}
				
				// Watching "calculate" elements
				{
					XmlUtils.search_named_children(node, NAME.CALCULATE, (node) => {
						//"name"->fundamental value.
						string name = XmlUtils.parse_prop<string>(node, NAME.NAME, true, XmlUtils.get_str);
						
						if(overrideMap.has_key(name)){
							return true;
						}
						
						//"method"->calculation method.
						string method = XmlUtils.parse_prop<string>(node, NAME.METHOD, true, XmlUtils.get_str);
						
						//"coeff"->Multiply the received value.
						double coeff = XmlUtils.parse_prop<double?>(node, NAME.COEFF, false, XmlUtils.parse_double, 1.0);
						
						//"group"->Which panel is destination to plot this serie?
						int def_grp = XmlUtils.parse_prop<int>(node, NAME.GROUP, false, XmlUtils.parse_int, 0);
						
						//"legend"->legend. if empty, same as "name".
						string legend = XmlUtils.parse_prop<string>(node, NAME.LEGEND, false, XmlUtils.get_str, name);
						
						//"color"->color code
						string color = XmlUtils.parse_prop<string>(node, NAME.COLOR, false, XmlUtils.get_str, "#ffffff");
						
						//"priority"->lower will be calculated earlier. bigger will be later(=So, bigger can use lower's value)
						int priority = XmlUtils.parse_prop<int>(node, NAME.PRIORITY, false, XmlUtils.parse_int, 0);
						
						//"for-plot"->if "false", then only for calculating but not for plotting.
						bool for_plot = bool.parse(XmlUtils.parse_prop<string>(node, NAME.FOR_PLOT, false, XmlUtils.get_str, "true"));
						
						var wentry = this.makeSerieButton(null, legend, name, color, def_grp);
						
						if(!this.onPrepareSerieCalculate(legend, name, coeff, method, priority)){
							return true;
						}
						if(for_plot){
							this.onPrepareSeriePlot(legend, name);
						}
						else{
							wentry.grp = -1;
						}
						
						if(wentry.grp >= 0){
							this.dui.add_entry(null, wentry);
						}
						
						overrideMap[name] = wentry;
						
						//watch "arg" elements inside "calculate"
						XmlUtils.search_named_children(node, NAME.ARG, (node) => {
							string arg_name = XmlUtils.parse_prop<string>(node, NAME.NAME, true, XmlUtils.get_str);
							int shift = XmlUtils.parse_prop<int>(node, NAME.SHIFT, false, XmlUtils.parse_int, 0);
							if(overrideMap.has_key(arg_name)){
								var child_wentry = overrideMap[arg_name];
								this.onAppendCalculateArg(name, child_wentry.pack, (double)shift, legend);
							}
							return true;
						});
						
						//watch "const" elements inside "calculate"
						XmlUtils.search_named_children(node, NAME.CONST, (node) => {
							string arg_name = XmlUtils.parse_prop<string>(node, NAME.NAME, true, XmlUtils.get_str);
							string val = XmlUtils.parse_prop<string>(node, NAME.VALUE, false, XmlUtils.get_str, "");
							this.onAppendCalculateConst(name, arg_name, val);
							return true;
						});
						
						
						
						return true;
					});
				}
				
				// Watching "layout" elements
				{
					XmlUtils.search_named_children(node, NAME.LAYOUT, (node) => {
						
						//"name" on layout->E.g. What glitch do you want to performe?
						string layout_name = XmlUtils.parse_prop<string>(node, NAME.NAME, true, XmlUtils.get_str);
						XmlUtils.search_named_children(node, NAME.SERIE, (node) => {
							string src = XmlUtils.parse_prop<string>(node, NAME.SRC, true, XmlUtils.get_str);
							var or = overrideMap.get(src);
							if(or == null){
								throw new XmlUtils.ReadError.CONTENT_ERROR("\"src\" must be specified from <mapping name=\"name\">");
							}
							
							string legend = XmlUtils.parse_prop<string>(node, NAME.LEGEND, false, XmlUtils.get_str, src);
							int grp = XmlUtils.parse_prop<int>(node, NAME.GROUP, false, XmlUtils.parse_int, -1);
							string color = XmlUtils.parse_prop<string>(node, NAME.COLOR, false, XmlUtils.get_str);
							
							var wentry = this.makeSerieButton(or, legend, null, color, grp);
							if(wentry.grp >= 0){
								this.dui.add_entry(layout_name, wentry);
							}
							return true;
						});
						
						return true;
					});
					
				}
				
				overrideMap.clear();
				
				// Build "presets" from those SeriesStorage data.
				{
					var listStore = new Gtk.ListStore(1, typeof(string));
					//var cellRendererText = new Gtk.CellRendererText();
					Gtk.TreeIter iter;
					listStore.append(out iter);
					listStore.set(iter, 0, NAME.SHOW_ALL, -1);
					
					foreach(var entry in this.dui.layouts){
						listStore.append(out iter);
						listStore.set(iter, 0, entry.key, -1);
					}
					
					this.ui.presets.set_model(listStore);
					this.ui.presets.set_active(0);
				}
				
				// Finally, prepare for recording if this src is socket.
				if(rec_dir != null){
					print("record base dir is %s\n".printf(rec_dir));
					string out_xml = "";
					Xml.Node *root;
					Xml.Node *recv = null;
					out_doc = doc->copy(1);
					
					root = out_doc->get_root_element();
					node = null;
					//remove "exporter" element
					XmlUtils.search_named_children(root, NAME.EXPORTER, (child) => {
						node = child;
						return false;
					});
					if(node != null){
						node->unlink();
						if(node->doc == null){
							print("delete unlinked \"exporter\" node\n");
							delete node;
						}
					}
					
					//change "receiver" element
					// - delete "port" / change "protocol"->"file" / set "dir"->"data"
					XmlUtils.search_named_children(root, NAME.RECEIVER, (child) => {
						if((recv = child) == null){
							recv = new Xml.Node(null, NAME.RECEIVER);
							root->add_child(recv);
						}
						return false;
					}, true);
					
					//remove receiver->dest
					XmlUtils.search_named_children(recv, NAME.DEST, (child) => {
						child->unlink();
						if(child->doc == null){
							delete child;
						}
						return false;
					});
					
					//extract receiver->local
					XmlUtils.search_named_children(recv, NAME.LOCAL, (child) => {
						if((node = child) == null){
							node = new Xml.Node(null, NAME.LOCAL);
							recv->add_child(node);	
						}
						return false;
					}, true);
					
					node->set_prop(NAME.PROTOCOL, "file");
					node->set_prop(NAME.DIR, "data");
					
					out_doc->dump_memory(out out_xml);
					this.onPrepareRecording(rec_dir, out_xml, "data");
				}
			}
			catch(GLib.Error e){
				this.onInitError(filename, e.message);
				this.onBufferInitialize();
			}
			finally{
				if(doc != null){
					delete doc;
				}
				if(out_doc != null){
					delete out_doc;
				}
			}
			return;
		}
		
		
		private void setupGrpLabel(Gtk.Button ev_label, Gee.List<Gtk.ToggleButton> list){
			//ev_label.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK);
			//ev_label.button_release_event.connect((ev) => {
			ev_label.clicked.connect(() => {
				if(list == null || list.first == null){
					return;
				}
				var state = list[0].get_active();
				foreach(var btn in list){
					btn.set_active(!state);
				}
				//return true;
			});
		}
		
		private SeriesStorage.Entry makeSerieButton(SeriesStorage.Entry? src, string? legend, string? pack, string? color, int grp){
			
			SeriesStorage.Entry ret = new SeriesStorage.Entry();
			ret.state = true;
			if(src != null){
				ret.grp = src.grp;
				ret.legend = src.legend;
				ret.pack = src.pack;
				ret.color = src.color;
				ret.state = src.state;
			}
			
			if(legend != null){
				ret.legend = legend;
			}
			if(pack != null){
				ret.pack = pack;
			}
			if(color != null){
				ret.color = color;
			}
			if(grp >= 0){
				ret.grp = grp;
			}
			
			print("legend: %s, pack: %s, color: %s, grp: %d\n".printf(ret.legend, ret.pack, ret.color, ret.grp));
			return ret;
		}
		
		private void changePreset(string? name){
			print("selected preset=>%s\n".printf(name));
			//this.ui.series_list.clear();
			this.ui.series_list.foreach((elem) => {this.ui.series_list.remove(elem);});
			
			if(name == null){
				return;
			}
			
			var wlist = (name == NAME.SHOW_ALL) ? this.dui.layout_default : this.dui.layouts[name];
			int prev_grp = -1;
			// grp_ev_box: For toggling the buttons that belong to specified button.
			Gtk.Button grp_ev_btn = null;
			Gee.List<Gtk.ToggleButton> grp_list = new Gee.LinkedList<Gtk.ToggleButton>();
			foreach(var wentry in wlist){
				if(prev_grp != wentry.grp){
					if(grp_ev_btn != null){
						this.setupGrpLabel(grp_ev_btn, grp_list);
					}
					grp_ev_btn = new Gtk.Button.with_label("\"<Group[%d]>\"".printf(wentry.grp));
					grp_ev_btn.use_underline = true;
					grp_list = new Gee.LinkedList<Gtk.ToggleButton>();
					//grp_ev_box.add(new Gtk.Label("Group[%d]".printf(wentry.grp)));
					this.ui.series_list.insert(grp_ev_btn, -1);
					prev_grp = wentry.grp;
				}
				
				// Button for each Serie to toggle visible/invisible.
				var btn = new Gtk.ToggleButton.with_label(wentry.legend);
				
				btn.set_active(wentry.state);
				this.ui.series_list.insert(btn, -1);
				
				btn.toggled.connect(() => {
					wentry.state = btn.active;
					this.onVisibleChanged(wentry);
				});
				btn.toggled();
				grp_list.add(btn);
			}
			if(grp_ev_btn != null){
				this.setupGrpLabel(grp_ev_btn, grp_list);
			}
			this.ui.series_list.show_all();
		}
		
		private void readReceiver(Xml.Node *node, out string? rec_dir) throws GLib.Error{
			int port = 8934;
			string protocol = "udp";
			int rate_ms = 100;
			string src_dir = null;
			string err_str = "";
			//local
			XmlUtils.search_named_children(node, NAME.LOCAL, (child) => {
				port = XmlUtils.parse_prop<int>(child, NAME.PORT, false, XmlUtils.parse_int, port);
				protocol = XmlUtils.parse_prop<string>(child, NAME.PROTOCOL, false, XmlUtils.get_str, protocol);
				rate_ms = XmlUtils.parse_prop<int>(child, NAME.RATE_MS, false, XmlUtils.parse_int, rate_ms);
				src_dir = XmlUtils.parse_prop<string>(child, NAME.DIR, false, XmlUtils.get_str, "data");
				return false;
			});
			
			if(protocol != "file"){
				//dest: dir->recording base directory. If it isn't written, CWD instead.
				string tmp = "";
				XmlUtils.search_named_children(node, NAME.DEST, (child) => {
					tmp = XmlUtils.parse_prop<string>(child, NAME.DIR, false, XmlUtils.get_str, tmp);
					return false;
				});
				rec_dir = tmp;
			}
			else{
				rec_dir = ".";
			}
			
			if(!this.onReceiverConfirmed(protocol, port, rate_ms, src_dir, out err_str)){
				//print("%s\n".printf(err_str));
				throw new XmlUtils.ReadError.CONTENT_ERROR("Failure to setup external context\n%s".printf(err_str));
			}
			return;
		}
		
		
	}
	
}