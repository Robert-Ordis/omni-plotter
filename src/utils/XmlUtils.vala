namespace XmlUtils{
	
	public errordomain ReadError{
		PARSE_ERROR,
		CONTENT_ERROR,
	}
	
	public int parse_int(string s) throws GLib.Error{
		int ret;
		if(s == null){
			throw new ReadError.CONTENT_ERROR("Parse Error(int): Null");
		}
		
		if(!int.try_parse(s, out ret)){
			throw new ReadError.CONTENT_ERROR("Parse Error(int): %s".printf(s));
		}
		//print("read: %d, str: %s\n".printf(ret, s));
		
		return ret;
	}
	
	public int64 parse_int64(string s) throws GLib.Error{
		int64 ret;
		if(s == null){
			throw new ReadError.CONTENT_ERROR("Parse Error(int64): Null");
		}
		
		if(!int64.try_parse(s, out ret)){
			throw new ReadError.CONTENT_ERROR("Parse Error(int64): %s".printf(s));
		}
		//print("read: %d, str: %s\n".printf(ret, s));
		
		return ret;
	}
	
	public double? parse_double(string s) throws GLib.Error{
		double ret;
		if(s == null){
			throw new ReadError.CONTENT_ERROR("Parse Error(double): Null");
		}
		
		if(!double.try_parse(s, out ret)){
			throw new ReadError.CONTENT_ERROR("Parse Error(double): %s".printf(s));
		}
		//print("read: %d, str: %s\n".printf(ret, s));
		
		return ret;
	}
	
	public string get_str(string s) throws GLib.Error{
		return s;
	}
	
	public delegate T StrParser<T>(string str) throws GLib.Error;
	public T parse_prop<T>(Xml.Node *node, string name, bool throwIfWrong, StrParser<T> parse, T? def = null) throws GLib.Error{
		string? tmp = node->get_prop(name);
		T? ret = def;
		if(tmp == null && throwIfWrong){
			throw new ReadError.CONTENT_ERROR("[%s:%s]->NOT FOUND".printf(node->name, name));
		}
		
		if(tmp != null){
			try{
				ret = parse(tmp);
			}
			catch(GLib.Error e){
				if(throwIfWrong){
					throw e;
				}
				ret = def;
			}
		}
		return ret;
	}
	
	public delegate bool NodeTreater(Xml.Node *node) throws GLib.Error;
	public void search_named_children(Xml.Node *parent, string name, NodeTreater each_node, bool call_if_null = false) throws GLib.Error{
		bool found = false;
		if(parent != null){
			for(Xml.Node *iter = parent->children; iter != null;){
				Xml.Node *next = iter->next;
				if(iter->type != Xml.ElementType.ELEMENT_NODE){
					iter = next;
					continue;
				}
				
				if(iter->name == name){
					found = true;
					if(!each_node(iter)){
						break;
					}
				}
				iter = next;
			}
		}
		if(!found && call_if_null){
			each_node(null);
		}
	}
	
}