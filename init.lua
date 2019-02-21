
storage_interface = {}

storage_interface.storage_nodes = {
	"default:chest",
	"default:chest_open",
	"default:chest_locked",
	"default:chest_locked_open"
}

storage_interface.connection_nodes = {
	"storage_interface:storage_interface",
	"storage_interface:storage_connector",
	"storage_interface:storage_connector_embedded"
}

if minetest.get_modpath("technic_chests") then
	table.insert(storage_interface.storage_nodes, "technic:iron_chest")
	table.insert(storage_interface.storage_nodes, "technic:iron_locked_chest")
	table.insert(storage_interface.storage_nodes, "technic:copper_chest")
	table.insert(storage_interface.storage_nodes, "technic:copper_locked_chest")
	table.insert(storage_interface.storage_nodes, "technic:silver_chest")
	table.insert(storage_interface.storage_nodes, "technic:silver_locked_chest")
	table.insert(storage_interface.storage_nodes, "technic:gold_chest")
	table.insert(storage_interface.storage_nodes, "technic:gold_locked_chest")
	table.insert(storage_interface.storage_nodes, "technic:mithril_chest")
	table.insert(storage_interface.storage_nodes, "technic:mithril_locked_chest")
end

if minetest.get_modpath("connected_chests") then
	table.insert(storage_interface.storage_nodes, "default:chest_connected_left")
	table.insert(storage_interface.storage_nodes, "default:chest_locked_connected_left")
	table.insert(storage_interface.connection_nodes, "default:chest_connected_right")
	table.insert(storage_interface.connection_nodes, "default:chest_locked_connected_right")
end

-- helper functions

-- before 5.0
function core.rgba(r, g, b, a)
	return a and string.format("#%02X%02X%02X%02X", r, g, b, a) or
	string.format("#%02X%02X%02X", r, g, b)
end

local function table_contains(t, v)
	for _, i in ipairs(t) do
		if i == v then
			return true
		end
	end
	return false
end

local function table_contains_table(t, v)
	for _, i in ipairs(t) do
		local c = 0
		local l = 0
		for m, k in pairs(i) do
			l = l+1
			if v[m] == k then 
				c = c+1
			end
		end
		if c == l then
			return true
		end
	end
end

local function pos_to_string(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function create_changed_pos(pos, x, y, z)
	local new_pos = table.copy(pos)
	new_pos.x = new_pos.x + x
	new_pos.y = new_pos.y + y
	new_pos.z = new_pos.z + z
	return new_pos
end

local function get_connected_nodes(pos, player)
	local p1 = create_changed_pos(pos, 10, 10, 10)
	local p2 = create_changed_pos(pos, -10, -10, -10)
	local pos_table = {pos}
	for _, tpos in ipairs(pos_table) do
		local check_pos = {
			create_changed_pos(tpos, 1, 0, 0),
			create_changed_pos(tpos, -1, 0, 0),
			create_changed_pos(tpos, 0, 1, 0),
			create_changed_pos(tpos, 0, -1, 0),
			create_changed_pos(tpos, 0, 0, 1),
			create_changed_pos(tpos, 0, 0, -1)
		}
		for _, cpos in ipairs(check_pos) do
			local nodename = minetest.get_node(cpos).name
			if (table_contains(storage_interface.storage_nodes, nodename) or 
					table_contains(storage_interface.connection_nodes, nodename)) and 
					not table_contains_table(pos_table, cpos) then
				table.insert(pos_table, cpos)
			end
		end
	end
	local rc = 0
	for k = 1, #pos_table do
		local kpos = pos_table[k - rc]
		local owner = minetest.get_meta(kpos):get_string("owner")
		if table_contains(storage_interface.connection_nodes, minetest.get_node(kpos).name) or
				(owner ~= "" and owner ~= player and player ~= ".ignore_player") then
			table.remove(pos_table, k - rc)
			rc = rc + 1
		end
	end
	return pos_table
end

local function match_filter(item_name, filter)
	if filter == "" then
		return true
	end
	local filter_table = string.split(filter, ",", false, -1)
	for _, filter_string in ipairs(filter_table) do
		if filter_string ~= "" then
			if string.sub(filter_string, 1, 6) == "group:" then
				if minetest.get_item_group(item_name, string.sub(filter_string, 7)) > 0 then
					return true
				end
			elseif string.sub(filter_string, 1, 1) == '"' and
					string.sub(filter_string, string.len(filter_string)) == '"' then
				if string.sub(filter_string, 2, string.len(filter_string)-1) == item_name then
					return true
				end
			else
				if string.find(item_name, filter_string) then
					return true
				end
			end
		end
	end
	return false
end

-- storage_inv functions

local function storage_remove_item(pos, stack, match_meta_and_wear, player)
	local nodes = get_connected_nodes(pos, player)
	local take_count = stack:get_count(stack)
	local return_stack = ItemStack(nil)
	local ostack = stack:get_name()
	if match_meta_and_wear == true then
		ostack = stack:peek_item(1):to_string()
	end
	for _, tpos in ipairs(nodes) do
		local meta = minetest.get_meta(tpos)
		local inv = meta:get_inventory()
		for listname, list in pairs(inv:get_lists()) do
			for i, istack in pairs(list) do
				local oistack = istack:get_name()
				if match_meta_and_wear == true then
					oistack = istack:peek_item(1):to_string()
				end
				if ostack == oistack then
					local available_count = istack:get_count()
					
					if take_count <= available_count then
						return_stack:add_item(istack:take_item(take_count))
						inv:set_stack(listname, i, istack)
						return return_stack
					else
						return_stack:add_item(istack:take_item(available_count))
						inv:set_stack(listname, i, istack)
						take_count = take_count - available_count
					end
				end
			end
		end
	end
	if not return_stack:is_empty() then
		return return_stack
	end
	return false
end

-- not perfect 
local function storage_room_for_item(pos, stack, player)
	local nodes = get_connected_nodes(pos, player)
	for _, tpos in ipairs(nodes) do
		local meta = minetest.get_meta(tpos)
		local inv = meta:get_inventory()
		local filter = meta:get_string("storage_interface_filter_string")
		if match_filter(stack:get_name(), filter) then
			for listname, _ in pairs(inv:get_lists()) do
				if inv:room_for_item(listname, stack) then
					return true
				end
			end
		end
	end
	return false
end

-- not perfect 
local function storage_add_item(pos, stack, player)
	local nodes = get_connected_nodes(pos, player)
	local possible_destinations = {}
	for _, tpos in ipairs(nodes) do
		local meta = minetest.get_meta(tpos)
		local inv = meta:get_inventory()
		local filter = meta:get_string("storage_interface_filter_string")
		if match_filter(stack:get_name(), filter) then
			for listname, _ in pairs(inv:get_lists()) do
				if inv:room_for_item(listname, stack) then
					local priority = meta:get_int("storage_interface_priority") or 0
					table.insert(possible_destinations, {pos = tpos, listname = listname, priority = priority})
				end
			end
		end
	end
	if not possible_destinations[1] then
		return stack
	end
	table.sort(possible_destinations, function(e1, e2)
		return e1.priority > e2.priority
	end)
	local meta = minetest.get_meta(possible_destinations[1].pos)
	local inv = meta:get_inventory()
	return inv:add_item(possible_destinations[1].listname, stack)
end

-- storage_table functions

local function get_storage_table(pos, player)
	local pos_table = get_connected_nodes(pos, player)
	local storage_table = {}
	for _, tpos in ipairs(pos_table) do
		local meta = minetest.get_meta(tpos)
		local inv = meta:get_inventory()
		for list, _ in pairs(inv:get_lists()) do
			for i = 1, inv:get_size(list), 1 do
				table.insert(storage_table, {
					pos = tpos,
					listname = list,
					index = i,
					itemstack = inv:get_stack(list, i),
					priority = meta:get_int("storage_interface_priority") or 0,
					filter = meta:get_string("storage_interface_filter_string") or ""
				})
			end
		end
	end
	return storage_table
end

local function get_oikt_index(itemstack, ignore_wam)
	local index = ""
	if ignore_wam == "false" then
		local itemstack_table = itemstack:to_table() or {}
		itemstack_table.count = 1
		index = ItemStack(itemstack_table):to_string()
	else
		index = itemstack:get_name()
	end
	return index
end

local function get_one_item_kind_table(storage_table, ignore_wam)
	local out_table = {}
	for _, entry in ipairs(storage_table) do
		local name = get_oikt_index(entry.itemstack, ignore_wam)
		out_table[name] = out_table[name] or {}
		local stack_count = entry.itemstack:get_count()
		local oikt_count = out_table[name].count or 0
		local oc_stack_count = entry.count
		if oc_stack_count then
			out_table[name].count = oc_stack_count
		else
			out_table[name].count = stack_count + oikt_count
		end
		table.insert(out_table[name], entry)
		
	end
	for _, entry_table in pairs(out_table) do
		table.sort(entry_table, function(entry1, entry2)
			return entry1.itemstack:get_count() > entry2.itemstack:get_count()
		end)
	end
	return out_table
end

local function sort_storage_table(storage_table, mode, ignore_wam)
	if mode == "count" then
		local oikt = get_one_item_kind_table(storage_table, ignore_wam)
		for _, e in ipairs(storage_table) do
			local name = get_oikt_index(e.itemstack, ignore_wam)
			if not e.count then
				if oikt[name] then
					e.count = oikt[name].count
				else
					e.count = 0
				end
			end
		end
		local ioikt = {}
		for _, ioikt_e in pairs(oikt) do
			table.insert(ioikt, ioikt_e)
		end
		table.sort(ioikt, function(entry1, entry2)
			local p1 = entry1.count
			local p2 = entry2.count
			if p1 == p2 then
				local itemstack1 = entry1[1].itemstack
				local itemstack2 = entry2[1].itemstack
				local name1 = itemstack1:get_name()
				local name2 = itemstack2:get_name()
				if name1 == name2 then
					p2 = itemstack1:get_wear()
					p1 = itemstack2:get_wear()
				else
					local nst = {}
					nst[1] = name1
					nst[2] = name2
					table.sort(nst)
					if nst[1] == name1 and nst[2] == name2 then
						return true
					else
						return false
					end
				end
			end
			return p1 > p2
		end)
		storage_table = {}
		for _, entry_table in ipairs(ioikt) do
			for _, entry in ipairs(entry_table) do
				table.insert(storage_table, entry)
			end
		end
	else
		table.sort(storage_table, function(entry1, entry2)
			local p1 = 0
			local p2 = 0
			local itemstack1 = entry1.itemstack
			local itemstack2 = entry2.itemstack
			local name1 = itemstack1:get_name()
			local name2 = itemstack2:get_name()
			if name1 == name2 then
				p1 = itemstack2:get_count()
				p2 = itemstack1:get_count()
				if p1 == p2 then
					p1 = itemstack1:get_wear()
					p2 = itemstack2:get_wear()
				end
			else
				local nst = {}
				nst[1] = name1
				nst[2] = name2
				table.sort(nst)
				if nst[1] == name1 and nst[2] == name2 then
					return true
				else
					return false
				end
			end
			return p1 < p2
		end)
	end
	return storage_table
end

-- storage_interface functions

local function get_color(stack_count)
	local ratio = 185
	local red, green, blue = 0, 0, 0
	if stack_count <= 1 then
		red = 235-math.floor(215*((stack_count-1)^2))
		green = red
		blue = red
	else
		local r = math.floor((1-math.exp(-0.0141*stack_count))*1200) -- 32 stacks about red
		green = 255
		red = 75 + r
		if red >= 255 then
			r = r - (255-75)
			red = 255
			green = 255 - r
			if green <= 0 then
				r = r - 255
				green = 0
				blue = r
				if blue >= 255 then
					r = r - 255
					blue = 255
					red = 255 - r
					if red <= 0 then
						r = r - 255
						red = 0
						green = r
					end
				end
			end
		end
	end
	local color = minetest.rgba(red, green, blue)
	return "gui_hb_bg.png^[colorize:".. color ..":".. ratio .."]"
end

local function storage_table_to_formspec(storage_table, xpos, ypos, l, h, page)
	local d_table = {}
	local formspec = ""
	local lc = 0
	local hc = 1
	for i = 1, l * h, 1 do
		d_table[i] = storage_table[i + (page-1) * l * h]
	end
	for _, entry in ipairs(d_table) do
		lc = lc + 1
		if lc > l then
			lc = 1
			hc = hc + 1
			if hc > h then
				break
			end
		end
		local string_pos = pos_to_string(entry.pos)
		formspec = formspec ..
			"list[nodemeta:".. string_pos ..";".. 
			entry["listname"] ..";"..
			xpos + lc - 1 ..",".. hc + ypos - 1 ..";"..
			"1,1;".. entry.index -1 .."]" ..
			"listring[nodemeta:" .. string_pos .. ";".. entry["listname"] .."]" ..
			"listring[current_player;main]"..
			"listring[current_player;nothing]"
	end
	return formspec
end

local function set_fake_inv(oikt, xpos, ypos, l, h, page, pos, sorting_mode, ignore_wam, display_count)
	local storage_table = {}
	for i, en in pairs(oikt) do
		en[1].count = en.count
		table.insert(storage_table, en[1])
	end
	storage_table = sort_storage_table(storage_table, sorting_mode, ignore_wam)
	local d_table = {}
	for i = 1, l * h, 1 do
		d_table[i] = storage_table[i + (page-1) * l * h]
	end
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local formspec = ""
	local lc = 0
	local hc = 1
	for i, entry in ipairs(d_table) do
		inv:set_stack("fake_inv", i, entry.itemstack)
		local count = entry.count
		local itemstack = inv:get_stack("fake_inv", i)
		local max_scount = itemstack:get_stack_max()
		if ignore_wam == "true" then
			itemstack:get_meta():from_table(nil)
			itemstack:set_wear(0)
		end
		if count > max_scount then
			itemstack:set_count(max_scount)
		else
			itemstack:set_count(count)
		end
		inv:set_stack("fake_inv", i, itemstack)
		lc = lc + 1
		if lc > l then
			lc = 1
			hc = hc + 1
			if hc > h then
				break
			end
		end
		local string_pos = pos_to_string(pos)
		if display_count == "number" then
			formspec = formspec ..
				"label[".. xpos + lc - 0.9 ..",".. (hc + ypos - 0.4) * 1.4 ..";".. entry.count .."]" ..
				"list[nodemeta:".. string_pos ..";".. 
				"fake_inv;".. xpos + lc - 1 ..",".. (hc + ypos - 1) * 1.4 ..";"..
				"1,1;".. lc - 1 + (hc - 1) * l .."]" ..
				"listring[nodemeta:" .. string_pos .. ";fake_inv]" ..
				"listring[current_player;main]"..
				"listring[current_player;nothing]"
		elseif display_count == "color" then
			formspec = formspec ..
				"list[nodemeta:".. string_pos ..";".. 
				"fake_inv;".. xpos + lc - 1 ..",".. hc + ypos - 1 ..";"..
				"1,1;".. lc - 1 + (hc - 1) * l .."]" ..
				"image[".. xpos + lc - 1 ..",".. hc + ypos - 1 ..
				";1,1;".. get_color(count/max_scount) .."]"..
				"listring[nodemeta:" .. string_pos .. ";fake_inv]" ..
				"listring[current_player;main]"..
				"listring[current_player;nothing]"
		else
			formspec = formspec ..
				"list[nodemeta:".. string_pos ..";".. 
				"fake_inv;".. xpos + lc - 1 ..",".. hc + ypos - 1 ..";"..
				"1,1;".. lc - 1 + (hc - 1) * l .."]" ..
				"listring[nodemeta:" .. string_pos .. ";fake_inv]" ..
				"listring[current_player;main]"..
				"listring[current_player;nothing]"
		end
	end
	return formspec
end

local function get_buttons(oikt, xpos, ypos, l, h, page, pos, sorting_mode, ignore_wam, display_count)
	local ignore_wam = true
	local storage_table = {}
	for i, en in pairs(oikt) do
		en[1].count = en.count
		table.insert(storage_table, en[1])
	end
	storage_table = sort_storage_table(storage_table, sorting_mode, ignore_wam)
	local d_table = {}
	for i = 1, l * h, 1 do
		d_table[i] = storage_table[i + (page-1) * l * h]
	end
	local formspec = ""
	local lc = 0
	local hc = 1
	for i, entry in ipairs(d_table) do
		lc = lc + 1
		if lc > l then
			lc = 1
			hc = hc + 1
			if hc > h then
				break
			end
		end
		local itemstack_name = entry.itemstack:get_name()
		local string_pos = pos_to_string(pos)
		if display_count == "number" then
			formspec = formspec ..
				"label[".. xpos + lc - 0.9 ..",".. (hc + ypos - 0.4) * 1.4 ..";".. entry.count .."]" ..
				"item_image_button[".. xpos + lc - 1 ..",".. (hc + ypos - 1) * 1.4 ..
				";1,1;".. itemstack_name ..";".. "storage_button_" .. itemstack_name ..";]"
		elseif display_count == "color" then
			formspec = formspec ..
				"item_image_button[".. xpos + lc - 1 ..",".. hc + ypos - 1 ..
				";1,1;".. itemstack_name ..";".. "storage_button_" .. itemstack_name ..";]" ..
				"image[".. xpos + lc - 1 ..",".. hc + ypos - 1 ..
				";1,1;".. get_color(entry.count/entry.itemstack:get_stack_max()) .."]"
		else
			formspec = formspec ..
				"item_image_button[".. xpos + lc - 1 ..",".. hc + ypos - 1 ..
				";1,1;".. itemstack_name ..";".. "storage_button_" .. itemstack_name ..";]"
		end
	end
	return formspec
end

local function update_formspec(player, pos)
	local meta = minetest.get_meta(pos)
	local storage_table = get_storage_table(pos, player)
	local page = meta:get_int("page") or 1
	local max_page = 1
	local mode = meta:get_string("mode") or "actual_inv"
	local l = 15
	local h = 7
	
	local capacity = #storage_table
	local empty_slots = 0
	for i = 1, #storage_table, 1 do
		local stitemstack = storage_table[i - empty_slots].itemstack
		if stitemstack:is_empty() or stitemstack:get_name() == "" then
			table.remove(storage_table, i - empty_slots)
			empty_slots = empty_slots + 1
		end
	end 
	
	local sorting_mode = meta:get_string("sorting_mode") or "name"
	local sorting_modedis = ""
	if sorting_mode == "name" then
		sorting_modedis = "Name"
	elseif sorting_mode == "count" then
		sorting_modedis = "Count"
	end
	
	local ignore_wam = meta:get_string("ignore_wam") or "true"
	if mode == "buttons" then
		ignore_wam = "true"
	end
	local ignore_wamdis = ""
	if ignore_wam == "true" then
		ignore_wamdis = "True"
	elseif ignore_wam == "false" then
		ignore_wamdis = "False"
	end
	
	local display_count = meta:get_string("display_count") or "number"
	local display_countdis = ""
	if display_count == "number" then
		h = 5
		display_countdis = "Number"
	elseif display_count == "none" then
		display_countdis = "None"
	elseif display_count == "color" then
		display_countdis = "Color"
	end
	
	local search_field = meta:get_string("search_field") or ""
	do
		local kept_table = {}
		for si, se in ipairs(storage_table) do
			kept_table[si] = match_filter(se.itemstack:get_name(), search_field)
		end
		local rc = 0 
		for i = 1, #storage_table, 1 do
			if kept_table[i] ~= true then
				table.remove(storage_table, i - rc)
				rc = rc + 1
			end
		end
	end
	
	storage_table = sort_storage_table(storage_table, sorting_mode, ignore_wam)
	
	local shown = meta:get_string("shown") or "everything"
	local showndis = shown
	if shown == "everything" then
		showndis = "Everything"
	elseif shown == "nodes" then
		showndis = "Nodes"
		local rc = 0
		for i = 1, #storage_table, 1 do
			if not minetest.registered_nodes[storage_table[i - rc].itemstack:get_name()] then
				table.remove(storage_table, i - rc)
				rc = rc + 1
			end
		end
	elseif shown == "craftitems" then
		showndis = "Craftitems"
		local rc = 0
		for i = 1, #storage_table, 1 do
			if not minetest.registered_craftitems[storage_table[i - rc].itemstack:get_name()] then
				table.remove(storage_table, i - rc)
				rc = rc + 1
			end
		end
	elseif shown == "tools" then
		showndis = "Tools"
		local rc = 0
		for i = 1, #storage_table, 1 do
			if not minetest.registered_tools[storage_table[i - rc].itemstack:get_name()] then
				table.remove(storage_table, i - rc)
				rc = rc + 1
			end
		end
	end
	
	local modedis = mode
	local st_form = ""
	if mode == "actual_inv" then
		h = 7
		modedis = "Actual Inventory"
		max_page = math.ceil(#storage_table/(l*h))
		if max_page < 1 then
			max_page = 1
		end
		if page > max_page then 
			page = max_page
			meta:set_int("page", page)
		end
		if page < 1 then
			page = 1
			meta:set_int("page", page)
		end
		st_form = storage_table_to_formspec(storage_table, 0, 0, l, h, page)
	elseif mode == "fake_inv" then
		modedis = "Fake Inventory"
		local oikt = get_one_item_kind_table(storage_table, ignore_wam)
		local oiktl = 0
		for _, _ in pairs(oikt) do
			oiktl = oiktl + 1
		end
		max_page = math.ceil(oiktl/(l*h))
		if max_page < 1 then
			max_page = 1
		end
		if page > max_page then 
			page = max_page
			meta:set_int("page", page)
		end
		if page < 1 then
			page = 1
			meta:set_int("page", page)
		end
		st_form = set_fake_inv(oikt, 0, 0, l, h, page, pos, sorting_mode, ignore_wam, display_count) 
	elseif mode == "buttons" then
		modedis = "Buttons"
		local oikt = get_one_item_kind_table(storage_table, ignore_wam)
		local oiktl = 0
		for _, _ in pairs(oikt) do
			oiktl = oiktl + 1
		end
		max_page = math.ceil(oiktl/(l*h))
		if max_page < 1 then
			max_page = 1
		end
		if page > max_page then 
			page = max_page
			meta:set_int("page", page)
		end
		if page < 1 then
			page = 1
			meta:set_int("page", page)
		end
		st_form = get_buttons(oikt, 0, 0, l, h, page, pos, sorting_mode, ignore_wam, display_count) 
	end
	
	local rb_mode = meta:get_string("rb_mode") or "settings"
	local rb_formspec = ""
	if rb_mode == "crafting" then
		rb_formspec = "label[13,7.2;Crafting]" ..
			"list[current_player;craft;12,9.2;3,3;]" ..
			"list[current_player;craftpreview;13,8;1,1;]" ..
			"listring[current_player;craft]" ..
			"listring[current_player;main]"
	elseif rb_mode == "settings" then
		local dbuttons = "label[11.6,10.3;Ignore meta and wear: ".. ignore_wamdis .."]" ..
			"button[14,10.1;1,1;change_ignore_wam;Change]"
		local ibuttons = "label[11.6,11;Display count: ".. display_countdis .."]" ..
			"button[14,10.8;1,1;change_display_count;Change]"
		if mode == "buttons" then
			local items_on_click = meta:get_string("items_on_click") or "one_stack"
			local items_on_clickdis = items_on_click
			if items_on_click == "one_stack" then
				items_on_clickdis = "One stack"
			elseif items_on_click == "all" then
				items_on_clickdis = "All"
			elseif items_on_click == "one_item" then
				items_on_clickdis = "One item"
			end
			dbuttons = "label[11.6,10.3;Items on click: ".. items_on_clickdis .."]" ..
				"button[14,10.1;1,1;change_items_on_click;Change]"
		end
		if mode == "actual_inv" then
			ibuttons = "field[11.9,11.4;2,1;infotext;Infotext;".. minetest.formspec_escape(meta:get_string("infotext")) .."]" ..
				"button[14,11.1;1,1;set_infotext;Set]" ..
				"field_close_on_enter[infotext;false]"
		end
		rb_formspec = "label[13,7.2;Settings]" ..
			"label[11.6,8.2;Mode: ".. modedis .."]" ..
			"button[14,8;1,1;change_mode;Change]" ..
			"label[11.6,8.9;Shown: ".. showndis .."]" ..
			"button[14,8.7;1,1;change_shown;Change]" ..
			"label[11.6,9.6;Sorting Mode: ".. sorting_modedis .."]" ..
			"button[14,9.4;1,1;change_sorting_mode;Change]" ..
			dbuttons ..
			ibuttons
	end
	
	local spos = pos_to_string(pos)
	local formspec = "size[15,12]" ..
		default.gui_bg ..
		default.gui_bg_img ..
		default.gui_slots ..
		"list[nodemeta:" .. spos .. ";input;0,10.2;3,2;]" ..
		"label[0,9.7;Input:]" ..
		"listring[current_player;main]" ..
		"listring[nodemeta:" .. spos .. ";input]" ..
		"listring[current_player;nothing]" ..
		st_form ..
		
		"label[0,7.2;Page: ".. page .." of ".. max_page .."]" ..
		"label[0,7.9;Capacity: ".. capacity - empty_slots .." of ".. capacity .."]" ..
		"button[3.1,7;0.9,1;first;|<--]"..
		"button[3.8,7;0.9,1;threeback;<<--]"..
		"button[4.5,7;0.9,1;back;<--]"..
		"button[5.2,7;0.9,1;next;-->]"..
		"button[5.9,7;0.9,1;threenext;-->>]"..
		"button[6.6,7;0.9,1;last;-->|]"..
		
		"button[10.5,7;1,1;search;Search]"..
		"button[11.4,7;1,1;reset;Reset]"..
		"field[7.8,7.3;3,1;search_field;;".. minetest.formspec_escape(search_field) .."]" ..
		"field_close_on_enter[search_field;false]"..
		
		"button[0.5,8.6;2,1;sort_storage;Sort storage]"..
		
		"list[current_player;main;3.5,8;8,1;]" ..
		"list[current_player;main;3.5,9.2;8,3;8]" ..
		
		"button[14,7;1,1;change_rb_mode;Change]"..
		rb_formspec ..
		default.get_hotbar_bg(3.5,8)
	
	minetest.show_formspec(player, "storage_interface:storage_interface", formspec)
end

local function sort_storage(pos, player)
	local meta = minetest.get_meta(pos)
	local storage_table = get_storage_table(pos, player)
	local sorted_storage_table = {}
	for _, ste in ipairs(storage_table) do
		local itemstack = ste.itemstack
		local item_name = itemstack:get_name()
		for _, sste in ipairs(sorted_storage_table) do
			local new_itemstack = sste.itemstack
			if new_itemstack:get_name() == item_name then
				itemstack = new_itemstack:add_item(itemstack)
			end
			if itemstack:is_empty() then
				break
			end
		end
		if not itemstack:is_empty() then
			table.insert(sorted_storage_table, ste)
		end
	end
	sorted_storage_table = sort_storage_table(sorted_storage_table, meta:get_string("sorting_mode"), "false")
	for i, e in ipairs(sorted_storage_table) do
		for id, ed in ipairs(storage_table) do
			if match_filter(e.itemstack:get_name(), ed.filter) and not storage_table[id].used then
				sorted_storage_table[i].can_store = true
				storage_table[id].used = true
				break
			end
		end
		if not sorted_storage_table[i].can_store then
			minetest.chat_send_player(player, "Your storage is to small to sort it.")
			return
		end
	end
	for _, entry in ipairs(storage_table) do
		local inv = minetest.get_meta(entry.pos):get_inventory()
		inv:set_stack(entry.listname, entry.index, "")
	end
	for _, entry in ipairs(sorted_storage_table) do
		storage_add_item(pos, entry.itemstack, player)
	end
end

local formspec_pos_si = {}

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "storage_interface:storage_interface" then
		return
	end
	local name = player:get_player_name()
	local pos = formspec_pos_si[name]
	if not pos then
		return
	end
	local meta = minetest.get_meta(pos)
	local page = meta:get_int("page")
	if fields.first then
		meta:set_int("page", 1)
	elseif fields.last then
		meta:set_int("page", 1000)
	elseif fields.threenext then
		meta:set_int("page", page + 3)
	elseif fields.threeback then
		meta:set_int("page", page - 3)
	elseif fields.next then
		meta:set_int("page", page + 1)
	elseif fields.back then
		meta:set_int("page", page - 1)
	elseif fields.change_mode then
		local mode = meta:get_string("mode")
		if mode == "actual_inv" then
			meta:set_string("mode", "fake_inv")
		elseif mode == "fake_inv" then
			meta:set_string("mode", "buttons")
		else
			meta:set_string("mode", "actual_inv")
		end
	elseif fields.change_shown then
		local shown = meta:get_string("shown")
		if shown == "everything" then
			meta:set_string("shown", "nodes")
		elseif shown == "nodes" then
			meta:set_string("shown", "craftitems")
		elseif shown == "craftitems" then
			meta:set_string("shown", "tools")
		else
			meta:set_string("shown", "everything")
		end
	elseif fields.change_rb_mode then
		local rb_mode = meta:get_string("rb_mode")
		if rb_mode == "crafting" then
			meta:set_string("rb_mode", "settings")
		else
			meta:set_string("rb_mode", "crafting")
		end
	elseif fields.change_sorting_mode then
		local sorting_mode = meta:get_string("sorting_mode")
		if sorting_mode == "name" then
			meta:set_string("sorting_mode", "count")
		else
			meta:set_string("sorting_mode", "name")
		end
	elseif fields.change_ignore_wam then
		local ignore_wam = meta:get_string("ignore_wam")
		if ignore_wam == "true" then
			meta:set_string("ignore_wam", "false")
		else
			meta:set_string("ignore_wam", "true")
		end
	elseif fields.change_items_on_click then
		local items_on_click = meta:get_string("items_on_click")
		if items_on_click == "one_stack" then
			meta:set_string("items_on_click", "one_item")
		elseif items_on_click == "one_item" then
			meta:set_string("items_on_click", "all")
		else
			meta:set_string("items_on_click", "one_stack")
		end
	elseif fields.change_display_count then
		local display_count = meta:get_string("display_count")
		if display_count == "number" then
			meta:set_string("display_count", "color")
		elseif display_count == "color" then
			meta:set_string("display_count", "none")
		else
			meta:set_string("display_count", "number")
		end
	elseif fields.set_infotext or fields.key_enter_field == "infotext" then
		meta:set_string("infotext", fields.infotext)
	elseif fields.search or fields.key_enter_field == "search_field" then
		meta:set_string("search_field", fields.search_field)
	elseif fields.reset then
		meta:set_string("search_field", "")
	elseif fields.sort_storage then
		sort_storage(pos, name)
	elseif meta:get_string("mode") == "buttons" then
		for fieldname, b in pairs(fields) do
			if b and string.sub(fieldname, 1, 15) == "storage_button_" then
				local playerinv = player:get_inventory()
				local bitemstack = ItemStack(string.sub(fieldname, 16))
				local items_on_click = meta:get_string("items_on_click") or "one_stack"
				if items_on_click == "one_stack" then
					bitemstack:set_count(bitemstack:get_stack_max())
					if playerinv:room_for_item("main", bitemstack) then
						local re_stack = storage_remove_item(pos, bitemstack, false, name)
						if re_stack then
							playerinv:add_item("main", re_stack)
						end
					end
				elseif items_on_click == "one_item" then
					bitemstack:set_count(1)
					if playerinv:room_for_item("main", bitemstack) then
						local re_stack = storage_remove_item(pos, bitemstack, false, name)
						if re_stack then
							playerinv:add_item("main", re_stack)
						end
					end
				elseif items_on_click == "all" then
					bitemstack:set_count(bitemstack:get_stack_max())
					for i = 1, 4*8 do
						local new_bitemstack = ItemStack(bitemstack:to_string())
						if playerinv:room_for_item("main", bitemstack) then
							local re_stack = storage_remove_item(pos, bitemstack, false, name)
							if re_stack then
								playerinv:add_item("main", re_stack)
							else
								break
							end
						else 
							break
						end
					end
				end
				break
			end
		end
	end
	
	if fields.quit then
		return true
	else
		update_formspec(name, pos)
	end
end)

local si_node_def = {
	description = "Storage Interface",
	tiles = {"default_chest_top.png", "default_chest_top.png",
		"default_chest_top.png","default_chest_top.png",
		"default_chest_top.png", "default_chest_top.png^storage_interface_front.png"},
	paramtype2 = "facedir",
	groups = {choppy = 2, oddly_breakable_by_hand = 2},
	legacy_facedir_simple = true,
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
	
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_int("page", 1)
		meta:set_string("mode", "actual_inv")
		meta:set_string("shown", "everything")
		meta:set_string("rb_mode", "settings")
		meta:set_string("sorting_mode", "name")
		meta:set_string("search_field", "")
		meta:set_string("ignore_wam", "false")
		meta:set_string("display_count", "number")
		meta:set_string("infotext", "Storage Interface")
		meta:set_string("items_on_click", "one_stack")
		local inv = meta:get_inventory()
		inv:set_size("input", 3*2)
		inv:set_size("fake_inv", 15*7)
	end,
	
	can_dig = function(pos,player)
		local meta = minetest.get_meta(pos);
		local inv = meta:get_inventory()
		return inv:is_empty("input")
	end,
	
	allow_metadata_inventory_move = function(pos, from_list, from_index,
			to_list, to_index, count, player)
		return 0
	end,
	
	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		if listname == "fake_inv" then
		
			-- trigger only one time
			local oldc_taken = player:get_attribute("storage_interface_taken")
			if oldc_taken then
				return oldc_taken
			end
			
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			local match_meta_and_wear = true
			if meta:get_string("ignore_wam") == "true" then
				match_meta_and_wear = false
			end
			local taken_stack = storage_remove_item(pos, stack, match_meta_and_wear, player:get_player_name())
			if not taken_stack then
				return 0
			end
			
			local count = taken_stack:get_count()
			inv:set_stack("fake_inv", index, taken_stack)
			player:set_attribute("storage_interface_taken", count)
			return count
		elseif listname == "input" then
			return stack:get_count()
		end
		return 0
	end,
	
	on_metadata_inventory_take = function(pos, listname, index, stack, player)
		if listname == "fake_inv" then
			player:set_attribute("storage_interface_taken", nil)
			
			-- Save items if a right-click swap has happened
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			local new_stack = inv:get_stack(listname, index)
			if not new_stack:item_fits(stack) then
				local inv = player:get_inventory()
				local overflow = inv:add_item("main", new_stack)
				if overflow and not overflow:is_empty() then
					minetest.item_drop(overflow, player, player:getpos())
				end
			end
			
		end
		update_formspec(player:get_player_name(), pos)
	end,
	
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname == "input" then
			if storage_add_item(pos, stack, player:get_player_name()):is_empty() then
				update_formspec(player:get_player_name(), pos)
				return(-1)
			end
		end
		return 0
	end,
	
	on_rightclick = function(pos, node, clicker)
		local name = clicker:get_player_name()
		formspec_pos_si[name] = pos
		update_formspec(name, pos)
	end,
	
	on_blast = function(pos)
		local drops = {}
		default.get_inventory_drops(pos, "input", drops)
		drops[#drops+1] = "storage_interface:storage_interface"
		minetest.remove_node(pos)
		return drops
	end
}

if minetest.get_modpath("pipeworks") then
	local tube_entry = "^pipeworks_tube_connection_wooden.png"
	si_node_def.tiles[1] = si_node_def.tiles[1] .. tube_entry
	si_node_def.tiles[2] = si_node_def.tiles[2] .. tube_entry
	si_node_def.tiles[3] = si_node_def.tiles[3] .. tube_entry
	si_node_def.tiles[4] = si_node_def.tiles[4] .. tube_entry
	si_node_def.tiles[5] = si_node_def.tiles[5] .. tube_entry .. "^[transformFX"
	si_node_def.groups.tubedevice = 1
	si_node_def.groups.tubedevice_receiver = 1
	si_node_def.after_place_node = pipeworks.after_place
	si_node_def.after_dig_node = pipeworks.after_dig
	si_node_def.tube = {
		insert_object = function(pos, node, stack, direction)
			return storage_add_item(pos, stack, ".ignore_player")
		end,
		can_insert = function(pos, node, stack, direction)
			return storage_room_for_item(pos, stack, ".ignore_player")
		end,
		input_inventory = "input",
		connect_sides = {left = 1, right = 1, back = 1, bottom = 1, top = 1},
	}
end

-- sfit functions

local formspec_pos_sfit = {}
local sfit_local_filter_string = {}

local function use_sfit(player, pos)
	local player_name = player:get_player_name()
	local meta = minetest.get_meta(pos)
	local old_filter_string = sfit_local_filter_string[player_name] or
			meta:get_string("storage_interface_filter_string") or ""
	sfit_local_filter_string[player_name] = old_filter_string
	local old_priority = meta:get_int("storage_interface_priority") or 0
	formspec_pos_sfit[player_name] = pos
	minetest.create_detached_inventory("storage_interface:sfit", {
		allow_put = function(inv, listname, index, stack, player)
			local player_name = player:get_player_name()
			local filter_string = sfit_local_filter_string[player_name]
			local stack_name = stack:get_name()
			if (not filter_string) or filter_string == "" then
				filter_string = '"'.. stack_name ..'"'
			else
				local filter_string_table = string.split(filter_string, ",", false, -1)
				for _, filter_stringi in ipairs(filter_string_table) do
					if string.sub(filter_stringi, 2, string.len(filter_stringi)-1) == stack_name then
						use_sfit(player, formspec_pos_sfit[player_name])
						return 0
					end
				end
				filter_string = filter_string ..',"'.. stack_name ..'"'
			end
			sfit_local_filter_string[player_name] = filter_string
			use_sfit(player, formspec_pos_sfit[player_name])
			return 0
		end
	}, player_name)
	local inv = minetest.get_inventory({type="detached", name="storage_interface:sfit"})
	inv:set_size("item_adder", 1)
	local formspec =
		"size[8,6]" ..
		default.gui_bg ..
		default.gui_bg_img ..
		default.gui_slots ..
		"list[detached:storage_interface:sfit;item_adder;2,0.5;1,1]" ..
		"label[2,0.1;Scan item]" ..
		"list[current_player;main;0,1.85;8,1;]" ..
		"list[current_player;main;0,3.08;8,3;8]" ..
		"listring[detached:storage_interface:sfit;item_adder]" ..
		"listring[current_player;main]" ..
		"field[3.3,0.8;3,1;sorting_filter_string;Sorting Filter String;".. minetest.formspec_escape(old_filter_string) .."]" ..
		"field[6.3,0.8;1,1;priority;Priority;".. minetest.formspec_escape(old_priority) .."]" ..
		"field_close_on_enter[sorting_filter_string;false]"..
		"field_close_on_enter[priority;false]"..
		"button[7,0.5;1,1;set_filter_string;Save]"..
		"button[0,0.5;2,1;scan_inventory;Scan node inventory]"..
		default.get_hotbar_bg(0,1.85)
	minetest.show_formspec(player_name, "storage_interface:sfit", formspec)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "storage_interface:sfit" then
		return
	end
	local player_name = player:get_player_name()
	local pos = formspec_pos_sfit[player_name]
	sfit_local_filter_string[player_name] = fields.sorting_filter_string
	if not pos then
		return
	end
	local meta = minetest.get_meta(pos)
	if fields.set_filter_string or
			fields.key_enter_field == "sorting_filter_string" or
			fields.key_enter_field == "priority" then
		meta:set_string("storage_interface_filter_string", sfit_local_filter_string[player_name])
		local priority = tonumber(fields.priority) or 0
		meta:set_int("storage_interface_priority", priority)
		minetest.chat_send_player(player_name, "Filter inscribed.")
		sfit_local_filter_string[player_name] = nil
	elseif fields.scan_inventory then
		local inv_list = meta:get_inventory():get_lists()
		local filter_string = sfit_local_filter_string[player_name]
		for _, ilist in pairs(inv_list) do
			for _, stack in ipairs(ilist) do
				local stack_name = stack:get_name() or ""
				if stack_name == "" then
				elseif (not filter_string) or filter_string == "" then
					filter_string = '"'.. stack_name ..'"'
				else
					local filter_string_table = string.split(filter_string, ",", false, -1)
					local contains_name = false
					for _, filter_stringi in ipairs(filter_string_table) do
						if string.sub(filter_stringi, 2, string.len(filter_stringi)-1) == stack_name then
							contains_name = true
						end
					end
					if not contains_name then
						filter_string = filter_string ..',"'.. stack_name ..'"'
					end
				end
			end
		end
		sfit_local_filter_string[player_name] = filter_string
	end
	if fields.quit then
		return true
	else
		use_sfit(player, pos)
	end
end)

-- item registration

minetest.register_node("storage_interface:storage_interface", si_node_def)

local scnb_size = 3/16
local sc_connects_to = table.copy(storage_interface.storage_nodes)
for _, i in ipairs(storage_interface.connection_nodes) do
	table.insert(sc_connects_to, i)
end
minetest.register_node("storage_interface:storage_connector", {
	description = "Storage Connection Cable",
	tiles = {"storage_interface_connector.png"},
	inventory_image = "storage_interface_connector_inv.png",
	wield_image = "storage_interface_connector_inv.png",
	groups = {choppy = 2, oddly_breakable_by_hand = 2, wood = 1, storage_interface_connect = 1},
	is_ground_content = false,
	sunlight_propagates = true,
	paramtype = "light",
	sounds = default.node_sound_wood_defaults(),
	drawtype = "nodebox",
	node_box = {
	type = "connected",
		fixed			= {-scnb_size, -scnb_size, 	-scnb_size, scnb_size,  scnb_size, scnb_size},
		connect_top		= {-scnb_size, -scnb_size, 	-scnb_size, scnb_size,  0.5, 	   scnb_size}, -- y+
		connect_bottom	= {-scnb_size, -0.5, 		-scnb_size, scnb_size,  scnb_size, scnb_size}, -- y-
		connect_front	= {-scnb_size, -scnb_size,	-0.5,  		scnb_size,  scnb_size, scnb_size}, -- z-
		connect_back	= {-scnb_size, -scnb_size, 	 scnb_size, scnb_size,  scnb_size, 0.5 		}, -- z+
		connect_left	= {-0.5,	   -scnb_size,	-scnb_size, scnb_size,  scnb_size, scnb_size}, -- x-
		connect_right	= {-scnb_size, -scnb_size,	-scnb_size, 0.5,   		scnb_size, scnb_size}, -- x+
	},
	connects_to = sc_connects_to,
})

minetest.register_node("storage_interface:storage_connector_embedded", {
	description = "Embedded Storage Connection Cable",
	tiles = {"default_chest_top.png^storage_interface_connector_middle.png"},
	groups = {choppy = 2, oddly_breakable_by_hand = 2, wood = 1},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
})

minetest.register_tool("storage_interface:sfit", {
	description = "Sorting Filter Inscribing Tool",
	inventory_image = "storage_interface_sfit.png",
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if not (pointed_thing and pointed_thing.type == "node" and user) then
			return
		end
		local pos = pointed_thing.under
		local player_name = user:get_player_name()
		local node = minetest.get_node(pos).name
		local meta = minetest.get_meta(pos)
		local owner = meta:get_string("owner") or ""
		if (owner ~= "" and owner ~= player_name) or minetest.is_protected(pos, player_name) then
			minetest.chat_send_player(player_name, "You do not own this node.")
			return
		end
		if table_contains(storage_interface.storage_nodes, node) then
			sfit_local_filter_string[player_name] = nil
			use_sfit(user, pos)
		else
			minetest.chat_send_player(player_name, "You can't inscribe this node.")
		end
		return
	end,
})

-- craft registration

minetest.register_craft({
	output = 'storage_interface:storage_interface',
	recipe = {
		{'default:steel_ingot', 'default:glass', 'default:steel_ingot'},
		{'group:wood', 'default:mese', 'group:wood'},
		{'group:wood', 'default:chest', 'group:wood'},
	}
})

minetest.register_craft({
	output = 'storage_interface:storage_connector 18',
	recipe = {
		{'group:stick', '', 'group:stick'},
		{'default:chest', 'group:wood', 'default:chest'},
		{'group:stick', '', 'group:stick'},
	}
})

minetest.register_craft({
	output = 'storage_interface:storage_connector_embedded 9',
	recipe = {
		{'group:wood', 'group:wood', 'group:wood'},
		{'group:wood', 'storage_interface:storage_connector', 'group:wood'},
		{'group:wood', 'group:wood', 'group:wood'},
	}
})

minetest.register_craft({
	output = 'storage_interface:sfit',
	recipe = {
		{'', 'default:mese_crystal_fragment', 'group:dye'},
		{'default:steel_ingot', 'default:chest', 'default:mese_crystal_fragment'},
		{'group:stick', 'default:steel_ingot', ''},
	}
})
