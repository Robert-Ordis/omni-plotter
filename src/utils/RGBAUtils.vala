namespace RGBAUtils {
	///\note parsing func of Gdk.RGBA won't work for #RRGGBBAA
	bool parse(ref Gdk.RGBA col, string str){
		var col_code = str.down();
		
		//first, parse color code as usual.
		var res = col.parse(col_code);
		if(!res){
			
			//If the first finished in failure, then split color part and alpha part.
			int tail_num = -1;
			float max = 1;
			switch(col_code.length){
			case 5:
				tail_num = 4;
				max = (float)0x0F;
				break;
			case 9:
				tail_num = 7;
				max = (float)0x00FF;
				break;
			case 13:
				tail_num = 10;
				max = (float)0x0FFF;
				break;
			case 17:
				tail_num = 13;
				max = (float)0x0000FFFF;
				break;
			}
			if(tail_num >= 0){
				int hex = 0;
				var alpha_str = col_code[tail_num: col_code.length];
				
				// parse splited color part.
				res = col.parse(col_code[0: tail_num]);
				if(res){
					// parse splited alpha part.
					alpha_str.scanf("%x", &hex);
					col.alpha = (float)hex / max;
				}
			}
		}
		
		return res;
	}
}