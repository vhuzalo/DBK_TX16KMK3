local NAME = "DBK_TX16KMK3"
local VERSION = "v1.0"
local WIDGET_DIR = "DBK_TX16KMK3"
local WIDGET_ROOT = "/WIDGETS/" .. WIDGET_DIR
local IMAGE_ROOT = WIDGET_ROOT .. "/image"
local MODEL_IMAGE_ROOT = WIDGET_ROOT .. "/modelImage"
local LOG_ROOT = WIDGET_ROOT .. "/logs"
local SYSTEM_LOG_ROOT = LOG_ROOT .. "/System"
local ENABLE_FLIGHT_REPORT_POPUP = false
local TopValue = 10
local crsf_field = { "Vbat", "Curr", "Hspd", "Capa", "Bat%", "Tesc", "Tmcu", "1RSS", "2RSS", "RQly", "Thr", "Vbec", "ARM", "Gov", "Vcel","Tmcu","PID#" }
local TELE_ITEMS = #crsf_field
local LOG_INFO_LEN = 22
local LOG_DATA_LEN = 115
local value_min_max = {}
local field_id = {}
local bank_info = { current = 1, name = "Bank 1" }
local tg_pic_obj
local bg_pic_obj
local hold_locked = false
local button_pressed = false
local cached_model_name = ""
local telemetry_initialized = false
local signal_lost = false
local last_rqly_status = false
local signal_lost_data = {
    model_name = "",
    flight_time = "00:00",
    max_power = 0,
    max_current = 0
}
local popup_button_positions = nil
local log_view_mode = 0
local model_list = {}
local selected_model_index = 1
local viewing_model_name = ""
local viewing_log_data = {}
local viewing_fly_number = 0
local model_index_file = SYSTEM_LOG_ROOT .. "/model_index.txt"
local file_name = ""
local file_path = ""
local file_obj
local log_info = ""
local log_data = {}
local fly_number = 0
local sele_number = 0
local second = { 0, 0, 0 }
local total_second = 0
local hours = 0
local minutes = { 0, 0 }
local seconds = { 0, 0 }
local power_max = { 0, 0 }
local write_en_flag = false
local goto_log_after_write = false
local arm_flag = false
local second_save = 0
local display_log_flag = false
local display_mode = 0
local last_arm_status = 0
local session_flight_count = 0
local current_flight_max_current = 0
local led_cache = { last_start_color = 0, last_end_color = 0 }
-- Curve recording feature is disabled

local rpm_buffer = {}
local rpm_collect_timer = 0
local rpm_collect_interval = 2
local rpm_file_path = ""
local rpm_start_time = ""
local current_buffer = {}
local current_start_time = ""
local voltage_buffer = {}
local voltage_start_time = ""
-- Multi-frame write state machine: 0=idle 1=write main log 2=write rpm 3=write current 4=write voltage
local write_state = 0
local write_snapshot = nil
-- Chart data cache: load once when entering chart view, clear when leaving
local chart_cache = nil
local chart_cache_key = ""
-- Chart render sampling step: 1=draw every point (finest), 5=draw every 5th point (fastest), default 3
local chart_render_step = 3

local options = {
    { "SquareColor", COLOR, WHITE },
    { "ValueColor", COLOR, GREEN },
    { "DispLED", BOOL, 0 },
    { "HoldSwitch", SWITCH, 0 },
    { "UserName", STRING, "DBK" }
}
local radioH = 0
local function build_default_log_info()
    return string.format("%d", getDateTime().year) .. '/' ..
        string.format("%02d", getDateTime().mon) .. '/' ..
        string.format("%02d", getDateTime().day) .. '|' ..
        "00:00:00" .. '|' ..
        "00\n"
end
local function load_model_index()
    local models = {}
    local file_info = fstat(model_index_file)
    if file_info and file_info.size > 0 then
        local file_obj = io.open(model_index_file, "r")
        if file_obj then
            local content = io.read(file_obj, file_info.size)
            io.close(file_obj)
            local start_pos = 1
            while start_pos <= #content do
                local end_pos = string.find(content, "\n", start_pos)
                if not end_pos then
                    end_pos = #content + 1
                end
                local line = string.sub(content, start_pos, end_pos - 1)
                local model_name = string.gsub(line, "\r", "")
                if model_name ~= "" then
                    table.insert(models, model_name)
                end
                start_pos = end_pos + 1
            end
        end
    end
    return models
end
local function update_model_index(model_name)
    if not model_name or model_name == "" or model_name == ">Rotorflight" then
        return
    end
    local models = load_model_index()
    local exists = false
    for i = 1, #models do
        if models[i] == model_name then
            exists = true
            break
        end
    end
    if not exists then
        table.insert(models, model_name)
        local file_obj = io.open(model_index_file, "w")
        if file_obj then
            for i = 1, #models do
                io.write(file_obj, models[i] .. "\n")
            end
            io.close(file_obj)
        end
    end
end
local function create(zone, options)
    local widget = {
        zone = zone,
        options = options
    }
    for i = 1, TELE_ITEMS do
        value_min_max[i] = { 0, 0, 0 }
        field_id[i] = { 0, false }
    end
    sele_number = 1
    display_log_flag = false
    display_mode = 0
    cached_model_name = ""
    telemetry_initialized = false
    for k, v in pairs(crsf_field) do
        local field_info = getFieldInfo(v)
        if field_info ~= nil then
            field_id[k][1] = field_info.id
            field_id[k][2] = true
        else
            field_id[k][1] = 0
            field_id[k][2] = false
        end
    end
    for i = 1, #second do
        second[i] = 0
    end
    total_second = 0
    write_en_flag = false
    arm_flag = false
    current_flight_max_current = 0
    signal_lost = false
    last_rqly_status = false
    telemetry_initialized = false
    file_name = "[" .. WIDGET_DIR .. "]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. ".log"
    file_path = LOG_ROOT .. "/" .. file_name
    local file_info = fstat(file_path)
    local read_count = 1
    if file_info ~= nil then
        if file_info.size > 0 then
            file_obj = io.open(file_path, "r")
            if file_obj then
                log_info = io.read(file_obj, LOG_INFO_LEN + 1)
                while true do
                    log_data[read_count] = io.read(file_obj, LOG_DATA_LEN + 1)
                    if #log_data[read_count] == 0 then
                        break
                    else
                        read_count = read_count + 1
                    end
                end
                io.close(file_obj)
                hours = string.sub(log_info, 12, 13)
                minutes[2] = string.sub(log_info, 15, 16)
                seconds[2] = string.sub(log_info, 18, 19)
                total_second = tonumber(string.sub(log_info, 12, 13)) * 3600
                total_second = total_second + tonumber(string.sub(log_info, 15, 16)) * 60
                total_second = total_second + tonumber(string.sub(log_info, 18, 19))
            else
                log_info = build_default_log_info()
                log_data = {}
            end
        else
            log_info = build_default_log_info()
        end
    else
        file_obj = io.open(file_path, "w")
        log_info = build_default_log_info()
        if file_obj then
            io.write(file_obj, log_info)
            io.close(file_obj)
        end
    end
    local str_temp = string.sub(log_info, 21, 23)
    if tonumber(str_temp) ~= nil then
        fly_number = tonumber(str_temp)
    end
    if fly_number == 0 then
        fly_number = 1
        sele_number = 1
        log_data[1] = "01|12:34:56|05:30|1850|025|2400|125.5|03500|25.2|22.8|+055|+025|+040|+020|-032|-072|-028|-065|100|095|080|12.6|11.8\n"
    end
    default_pic_obj = Bitmap.open(IMAGE_ROOT .. "/default.png")
    hold1_pic_obj = Bitmap.open(IMAGE_ROOT .. "/hold1.png")
    hold2_pic_obj = Bitmap.open(IMAGE_ROOT .. "/hold2.png")
    local current_model = model.getInfo().name
    if current_model and current_model ~= "" then
        update_model_index(current_model)
    end
    return widget
end
local function update(widget, options)
    widget.options = options
end
local function background(widget)
end
local function get_total_flight_count(model_name)
    if not model_name or model_name == "" then
        return 0
    end
    local safe_model_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local total_file_path = SYSTEM_LOG_ROOT .. "/totalall_[" .. safe_model_name .. "].txt"
    local file_info = fstat(total_file_path)
    if file_info and file_info.size > 0 then
        local file = io.open(total_file_path, "r")
        if file then
            local content = io.read(file, 100)
            io.close(file)
            local count = tonumber(content)
            if count then
                return count
            end
        end
    end
    return 0
end
local function increment_total_flight_count(model_name)
    if not model_name or model_name == "" then
        return
    end
    local safe_model_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local total_file_path = SYSTEM_LOG_ROOT .. "/totalall_[" .. safe_model_name .. "].txt"
    local current_count = get_total_flight_count(model_name)
    local new_count = current_count + 1
    local file = io.open(total_file_path, "w")
    if file then
        io.write(file, tostring(new_count))
        io.close(file)
    end
end
local function scan_model_logs()
    local models = load_model_index()
    local model_list = {}
    local model_flight_counts = {}
    for i = 1, #models do
        if models[i] ~= ">Rotorflight" and models[i] ~= "" then
            model_flight_counts[models[i]] = 0
        end
    end
    local current_date = getDateTime()
    local current_year = current_date.year
    local current_month = current_date.mon
    local current_day = current_date.day
    for day_offset = 0, 29 do
        local check_day = current_day - day_offset
        local check_month = current_month
        local check_year = current_year
        if check_day < 1 then
            check_month = check_month - 1
            if check_month < 1 then
                check_month = 12
                check_year = check_year - 1
            end
            check_day = 30 + check_day
        end
        local date_str = string.format("%d%02d%02d", check_year, check_month, check_day)
        for i = 1, #models do
            local model_name = models[i]
            if model_name ~= ">Rotorflight" and model_name ~= "" then
                local safe_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
                local file_name = "[".. safe_name .."]" .. date_str .. ".log"
                local file_path = LOG_ROOT .. "/" .. file_name
                local file_info = fstat(file_path)
                if file_info and file_info.size > 0 then
                    local file_obj = io.open(file_path, "r")
                    if file_obj then
                        local log_info = io.read(file_obj, LOG_INFO_LEN + 1)
                        io.close(file_obj)
                        if log_info and string.len(log_info) >= LOG_INFO_LEN then
                            local fly_count = tonumber(string.sub(log_info, 21, 22)) or 0
                            if fly_count > 0 then
                                model_flight_counts[model_name] = model_flight_counts[model_name] + fly_count
                            end
                        end
                    end
                end
            end
        end
    end
    for model_name, total_count in pairs(model_flight_counts) do
        table.insert(model_list, {
            name = model_name,
            log_count = total_count
        })
    end
    return model_list
end
local function load_model_logs(model_name)
    local safe_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local file_name = "[".. safe_name .."]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. ".log"
    local file_path = LOG_ROOT .. "/" .. file_name
    local file_info = fstat(file_path)
    if not file_info or file_info.size == 0 then
        return {fly_number = 0, log_data = {}}
    end
    local file_obj = io.open(file_path, "r")
    if not file_obj then
        return {fly_number = 0, log_data = {}}
    end
    local log_info = io.read(file_obj, 23)
    local fly_number = 0
    if log_info and string.len(log_info) >= 23 then
        fly_number = tonumber(string.sub(log_info, 21, 23)) or 0
    end
    local log_data = {}
    for i = 1, fly_number do
        log_data[i] = io.read(file_obj, 116)
    end
    io.close(file_obj)
    return {fly_number = fly_number, log_data = log_data}
end
-- Curve recording feature is disabled - write_rpm_data

local function write_rpm_data(model_name, flight_num, start_time, end_time, rpm_data)
    if not model_name or model_name == "" or #rpm_data == 0 then
        return
    end
    local safe_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local file_name = "[".. safe_name .."]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. "_rpm.txt"
    local file_path = LOG_ROOT .. "/" .. file_name
    local file_obj = io.open(file_path, "a")
    if file_obj then
        io.write(file_obj, string.format("#%02d|%s|%s\n", flight_num, start_time, end_time))
        local parts = {}
        for i = 1, #rpm_data do parts[i] = tostring(rpm_data[i]) end
        io.write(file_obj, table.concat(parts, ",") .. "\n")
        io.close(file_obj)
    end
end

-- Curve recording feature is disabled - write_current_data

local function write_current_data(model_name, flight_num, start_time, end_time, current_data)
    if not model_name or model_name == "" or #current_data == 0 then
        return
    end
    local safe_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local file_name = "[".. safe_name .."]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. "_electricity.txt"
    local file_path = LOG_ROOT .. "/" .. file_name
    local file_obj = io.open(file_path, "a")
    if file_obj then
        io.write(file_obj, string.format("#%02d|%s|%s\n", flight_num, start_time, end_time))
        local parts = {}
        for i = 1, #current_data do parts[i] = string.format("%.1f", current_data[i]) end
        io.write(file_obj, table.concat(parts, ",") .. "\n")
        io.close(file_obj)
    end
end

-- Curve recording feature is disabled - write_voltage_data

local function write_voltage_data(model_name, flight_num, start_time, end_time, voltage_data)
    if not model_name or model_name == "" or #voltage_data == 0 then
        return
    end
    local safe_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local file_name = "[".. safe_name .."]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. "_volt.txt"
    local file_path = LOG_ROOT .. "/" .. file_name
    local file_obj = io.open(file_path, "a")
    if file_obj then
        io.write(file_obj, string.format("#%02d|%s|%s\n", flight_num, start_time, end_time))
        local parts = {}
        for i = 1, #voltage_data do parts[i] = string.format("%.2f", voltage_data[i]) end
        io.write(file_obj, table.concat(parts, ",") .. "\n")
        io.close(file_obj)
    end
end

-- Curve recording feature is disabled - load_rpm_data
local function load_rpm_data(model_name, flight_num)
    if not model_name or model_name == "" then
        return nil
    end
    local safe_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local file_name = "[".. safe_name .."]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. "_rpm.txt"
    local file_path = LOG_ROOT .. "/" .. file_name
    local file_info = fstat(file_path)
    if not file_info or file_info.size == 0 then
        return nil
    end
    local file_obj = io.open(file_path, "r")
    if not file_obj then
        return nil
    end
    local content = io.read(file_obj, file_info.size)
    io.close(file_obj)
    local target_header = string.format("#%02d|", flight_num)
    local header_pos = string.find(content, target_header, 1, true)
    if not header_pos then
        return nil
    end
    local line_end = string.find(content, "\n", header_pos)
    if not line_end then
        return nil
    end
    local header_line = string.sub(content, header_pos, line_end - 1)
    local start_time = string.match(header_line, "#%d+|([^|]+)|")
    local end_time = string.match(header_line, "|([^|]+)$")
    local data_start = line_end + 1
    local data_end = string.find(content, "\n", data_start)
    if not data_end then
        data_end = #content + 1
    end
    local rpm_line = string.sub(content, data_start, data_end - 1)
    local rpm_values = {}
    for rpm_str in string.gmatch(rpm_line, "[^,]+") do
        local rpm = tonumber(rpm_str)
        if rpm then
            table.insert(rpm_values, rpm)
        end
    end
    if #rpm_values == 0 then
        return nil
    end
    return {
        start_time = start_time,
        end_time = end_time,
        rpm_values = rpm_values
    }
end

-- Curve recording feature is disabled - load_current_data

local function load_current_data(model_name, flight_num)
    if not model_name or model_name == "" then
        return nil
    end
    local safe_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local file_name = "[".. safe_name .."]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. "_electricity.txt"
    local file_path = LOG_ROOT .. "/" .. file_name
    local file_info = fstat(file_path)
    if not file_info or file_info.size == 0 then
        return nil
    end
    local file_obj = io.open(file_path, "r")
    if not file_obj then
        return nil
    end
    local content = io.read(file_obj, file_info.size)
    io.close(file_obj)
    local target_header = string.format("#%02d|", flight_num)
    local header_pos = string.find(content, target_header, 1, true)
    if not header_pos then
        return nil
    end
    local line_end = string.find(content, "\n", header_pos)
    if not line_end then
        return nil
    end
    local header_line = string.sub(content, header_pos, line_end - 1)
    local start_time = string.match(header_line, "#%d+|([^|]+)|")
    local end_time = string.match(header_line, "|([^|]+)$")
    local data_start = line_end + 1
    local data_end = string.find(content, "\n", data_start)
    if not data_end then
        data_end = #content + 1
    end
    local current_line = string.sub(content, data_start, data_end - 1)
    local current_values = {}
    for current_str in string.gmatch(current_line, "[^,]+") do
        local current = tonumber(current_str)
        if current then
            table.insert(current_values, current)
        end
    end
    if #current_values == 0 then
        return nil
    end
    return {
        start_time = start_time,
        end_time = end_time,
        current_values = current_values
    }
end

-- Curve recording feature is disabled - load_voltage_data

local function load_voltage_data(model_name, flight_num)
    if not model_name or model_name == "" then
        return nil
    end
    local safe_name = string.gsub(model_name, "[<>:\"/\\|?*]", "")
    local file_name = "[".. safe_name .."]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. "_volt.txt"
    local file_path = LOG_ROOT .. "/" .. file_name
    local file_info = fstat(file_path)
    if not file_info or file_info.size == 0 then
        return nil
    end
    local file_obj = io.open(file_path, "r")
    if not file_obj then
        return nil
    end
    local content = io.read(file_obj, file_info.size)
    io.close(file_obj)
    local target_header = string.format("#%02d|", flight_num)
    local header_pos = string.find(content, target_header, 1, true)
    if not header_pos then
        return nil
    end
    local line_end = string.find(content, "\n", header_pos)
    if not line_end then
        return nil
    end
    local header_line = string.sub(content, header_pos, line_end - 1)
    local start_time = string.match(header_line, "#%d+|([^|]+)|")
    local end_time = string.match(header_line, "|([^|]+)$")
    local data_start = line_end + 1
    local data_end = string.find(content, "\n", data_start)
    if not data_end then
        data_end = #content + 1
    end
    local voltage_line = string.sub(content, data_start, data_end - 1)
    local voltage_values = {}
    for voltage_str in string.gmatch(voltage_line, "[^,]+") do
        local voltage = tonumber(voltage_str)
        if voltage then
            table.insert(voltage_values, voltage)
        end
    end
    if #voltage_values == 0 then
        return nil
    end
    return {
        start_time = start_time,
        end_time = end_time,
        voltage_values = voltage_values
    }
end

local function get_bank_info(widget)
    if widget.options.BankSwitch ~= 0 then
        local bank_value = getValue(widget.options.BankSwitch) or 0
        local bank_num = 1
        if bank_value < -300 then
            bank_num = 1
        elseif bank_value > 300 then
            bank_num = 3
        else
            bank_num = 2
        end
        bank_info.current = bank_num
        return
    end
    local fm_value = getValue("FM")
    if fm_value ~= nil then
        local bank_num = math.floor(fm_value) + 1
        bank_info.current = math.max(1, math.min(6, bank_num))
        return
    end
    bank_info.current = 1
end
local function draw_rounded_rectangle(xs, ys, w, h, r, color)
    lcd.drawArc(xs + r, ys + r, r, 270, 360, color)
    lcd.drawArc(xs + r, ys + h - r, r, 180, 270, color)
    lcd.drawArc(xs + w - r, ys + r, r, 0, 90, color)
    lcd.drawArc(xs + w - r, ys + h - r, r, 90, 180, color)
    lcd.drawLine(xs + r, ys, xs + w - r, ys, SOLID, color)
    lcd.drawLine(xs + r, ys + h, xs + w - r, ys + h, SOLID, color)
    lcd.drawLine(xs, ys + r, xs, ys + h - r, SOLID, color)
    lcd.drawLine(xs + w, ys + r, xs + w, ys + h - r, SOLID, color)
end
local function fuel_percentage(xs, ys, capa, number, text_color)
    local color = lcd.RGB(255 - number * 2.55, number * 2.55, 0)
    if number ~= 0 and number ~= 100 then
        lcd.drawAnnulus(xs, ys, 45, 70, (100 - number) * 3.6, 360, color)
    end
    if number == 100 then
        lcd.drawAnnulus(xs, ys, 45, 70, 1, 360, color)
        lcd.drawAnnulus(xs, ys, 45, 70, -5, 5, color)
    end
    lcd.drawText(xs + 2, ys - 10, string.format("%d%%", number), CENTER + VCENTER + DBLSIZE + text_color)
    lcd.drawText(xs, ys + 15, string.format("%dmAh", capa), CENTER + VCENTER + text_color)
end
local function draw_ring_progress(xs, ys, value, max_value, size)
    local radius = size
    local ring_width = 8
    local segments = 20
    local gap = 3
    local angle_coverage = 270
    local segments_to_draw = 15
    local start_angle = -135
    local gray_color = lcd.RGB(80, 80, 80)
    value = math.max(0, math.min(max_value, value))
    local progress_percent = value / max_value
    local active_segments = math.floor(segments_to_draw * progress_percent)
    for i = 0, segments_to_draw - 1 do
        local angle_start = (360 / segments) * i + start_angle + gap / 2
        local angle_end = (360 / segments) * (i + 1) + start_angle - gap / 2
        local segment_color = gray_color
        if i < active_segments then
            local seg_percent = (i / (segments_to_draw - 1)) * 100
            local r = math.floor(seg_percent * 2.55)
            local g = math.floor(255 - (seg_percent * 2.55))
            local b = 0
            segment_color = lcd.RGB(r, g, b)
        end
        lcd.drawAnnulus(xs, ys, radius - ring_width, radius, angle_start, angle_end, segment_color)
    end
end
local function throttle_percentage_bar(xs, ys, thr_value, border_color, text_color)
    local bar_width = 150
    local bar_height = 20
    local fill_width = math.floor(bar_width * thr_value / 100)
    thr_value = math.max(0, math.min(100, thr_value))
    local color = lcd.RGB(thr_value * 2.55, 0, 255 - thr_value * 2.55)
    draw_rounded_rectangle(xs, ys, bar_width, bar_height, 8, border_color)
    if thr_value > 0 then
        if fill_width > 6 then
            lcd.drawFilledRectangle(xs + 2, ys + 2, fill_width - 4, bar_height - 4, color)
        end
    end
    lcd.drawText(xs + bar_width / 2, ys + bar_height / 2, string.format("%d%%", thr_value), CENTER + VCENTER + SMLSIZE + text_color)
end
local function rqly_signal_bars(xs, ys, rqly_percent, default_color)
    local block_size = 11
    local block_spacing = 17
    rqly_percent = math.max(0, math.min(100, rqly_percent))
    local active_blocks = math.floor((rqly_percent + 19) / 20)
    for i = 1, 5 do
        local block_x = xs + (i - 1) * block_spacing
        local block_y = ys
        local block_color = default_color
        if rqly_percent > 0 and i <= active_blocks then
            if i == 1 then
                block_color = RED
            elseif i == 2 then
                block_color = ORANGE
            elseif i == 3 then
                block_color = YELLOW
            elseif i == 4 then
                block_color = lcd.RGB(173, 255, 47)
            else
                block_color = GREEN
            end
        end
        lcd.drawFilledRectangle(block_x, block_y, block_size, block_size, block_color)
    end
end
local function rqly_signal_bars_ladder(xs, ys, rqly_percent, default_color, size)
    local bar_count = 6
    local bar_width = math.floor(6 * size)
    local bar_spacing = math.floor(2 * size)
    local base_height = math.floor(4 * size)
    local height_increment = math.floor(4 * size)
    rqly_percent = math.max(0, math.min(100, rqly_percent))
    local active_bars = math.floor((rqly_percent + 8) / 16.67)
    for i = 1, bar_count do
        local bar_x = xs + (i - 1) * (bar_width + bar_spacing)
        local bar_height = base_height + (i - 1) * height_increment
        local bar_y = ys - bar_height
        local bar_color = default_color
        if rqly_percent > 0 and i <= active_bars then
            if i == 1 then
                bar_color = RED
            elseif i == 2 then
                bar_color = ORANGE
            elseif i == 3 then
                bar_color = YELLOW
            elseif i == 4 then
                bar_color = lcd.RGB(173, 255, 47)
            elseif i == 5 then
                bar_color = lcd.RGB(0, 255, 0)
            else
                bar_color = GREEN
            end
        end
        lcd.drawFilledRectangle(bar_x, bar_y, bar_width, bar_height, bar_color)
    end
end
local function draw_gauge_meter(xs, ys, value, max_value, size, color, bg_color)
    local radius = size
    local start_angle = 180
    local end_angle = 270
    local range_angle = end_angle - start_angle
    value = math.max(0, math.min(max_value, value))
    local scale_steps = {0, 20, 40, 60, 80, 100}
    local scale_start = 190
    local scale_end = 260
    local scale_range = scale_end - scale_start
    for i = 1, #scale_steps do
        local step = scale_steps[i]
        local angle = scale_start + (step / 100) * scale_range
        local rad = math.rad(angle)
        local x1 = xs + math.cos(rad) * (radius * 0.80)
        local y1 = ys + math.sin(rad) * (radius * 0.80)
        local x2 = xs + math.cos(rad) * (radius * 0.92)
        local y2 = ys + math.sin(rad) * (radius * 0.92)
        lcd.drawLine(x1, y1, x2, y2, SOLID, color)
        if step % 20 == 0 then
            local text_x = xs + math.cos(rad) * (radius * 1.25)
            local text_y = ys + math.sin(rad) * (radius * 1.25)
            lcd.drawText(text_x, text_y, tostring(step), SMLSIZE + color)
        end
    end
    for tick = 0, 100, 4 do
        local angle = start_angle + (tick / 100) * range_angle
        local rad = math.rad(angle)
        local x1 = xs + math.cos(rad) * (radius * 0.86)
        local y1 = ys + math.sin(rad) * (radius * 0.86)
        local x2 = xs + math.cos(rad) * (radius * 0.92)
        local y2 = ys + math.sin(rad) * (radius * 0.92)
        lcd.drawLine(x1, y1, x2, y2, SOLID, bg_color)
    end
    local value_percent = value / max_value * 100
    local segments = 45
    local arc_start_angle = 270
    local arc_end_angle = 360
    for seg = 0, segments - 1 do
        local seg_start = arc_start_angle + (arc_end_angle - arc_start_angle) * (seg / segments)
        local seg_end = arc_start_angle + (arc_end_angle - arc_start_angle) * ((seg + 1) / segments)
        local seg_percent = (seg / segments) * 100
        local r = math.floor(seg_percent * 2.55)
        local g = math.floor(255 - (seg_percent * 2.55))
        local b = 0
        local seg_color = lcd.RGB(r, g, b)
        for w = 0, 5 do
            lcd.drawArc(xs, ys, radius * 0.92 + w, seg_start, seg_end, seg_color)
        end
    end
    local value_angle = start_angle + (value_percent / 100) * range_angle
    local arc_start = start_angle
    local arc_end = value_angle
    local pointer_angle = value_angle
    local pointer_rad = math.rad(pointer_angle)
    local offset_angle = 232
    local offset_rad = math.rad(offset_angle)
    local offset_distance = radius * 0.08
    local center_x = xs + math.cos(offset_rad) * offset_distance
    local center_y = ys + math.sin(offset_rad) * offset_distance
    local pointer_length = radius * 0.60
    local pointer_x = center_x + math.cos(pointer_rad) * pointer_length
    local pointer_y = center_y + math.sin(pointer_rad) * pointer_length
    lcd.drawLine(center_x, center_y, pointer_x, pointer_y, SOLID, color)
    lcd.drawLine(center_x + 1, center_y, pointer_x + 1, pointer_y, SOLID, color)
    lcd.drawLine(center_x, center_y + 1, pointer_x, pointer_y + 1, SOLID, color)
    lcd.drawLine(center_x - 1, center_y, pointer_x - 1, pointer_y, SOLID, color)
    lcd.drawLine(center_x, center_y - 1, pointer_x, pointer_y - 1, SOLID, color)
    lcd.drawFilledCircle(center_x, center_y, math.max(3, radius * 0.08), color)
end
local function draw_digital_display(x, y, value, num_digits, decimal_places, digit_size, color)
    local seg_width = digit_size * 0.6
    local seg_height = digit_size * 0.5
    local seg_thickness = digit_size * 0.15
    local digit_spacing = digit_size * 1.2
    local gray_color = lcd.RGB(80, 80, 80)
    local dot_size = seg_thickness
    local multiplier = math.pow(10, decimal_places)
    local int_part = math.floor(value)
    local dec_part = math.floor((value - int_part) * multiplier + 0.5)
    if dec_part >= multiplier then
        int_part = int_part + 1
        dec_part = 0
    end
    local max_int_value = math.pow(10, num_digits) - 1
    int_part = math.min(max_int_value, int_part)
    local int_value_digits = 0
    if int_part == 0 then
        int_value_digits = 1
    else
        int_value_digits = math.floor(math.log(int_part) / math.log(10)) + 1
    end
    local current_x = x
    for i = 0, num_digits - 1 do
        local divisor = math.pow(10, num_digits - 1 - i)
        local digit = math.floor(int_part / divisor) % 10
        local digit_color = gray_color
        local is_leading_zero = true
        if i >= (num_digits - int_value_digits) then
            digit_color = color
            is_leading_zero = false
        end
        draw_digit_segment(current_x, y, digit, seg_width, seg_height, seg_thickness, digit_color, gray_color)
        current_x = current_x + digit_spacing
    end
    if decimal_places > 0 then
        local dot_y = y + seg_height * 2 + seg_thickness * 2
        lcd.drawFilledRectangle(current_x - digit_spacing * 0.15, dot_y, dot_size, dot_size, color)
    end
    for i = 0, decimal_places - 1 do
        local divisor = math.pow(10, decimal_places - 1 - i)
        local digit = math.floor(dec_part / divisor) % 10
        draw_digit_segment(current_x, y, digit, seg_width, seg_height, seg_thickness, color, gray_color)
        current_x = current_x + digit_spacing
    end
end
local function draw_digit_segment(x, y, digit, seg_width, seg_height, seg_thickness, color, bg_color)
    local segments = {
        [0] = {1,1,1,1,1,1,0},
        [1] = {0,1,1,0,0,0,0},
        [2] = {1,1,0,1,1,0,1},
        [3] = {1,1,1,1,0,0,1},
        [4] = {0,1,1,0,0,1,1},
        [5] = {1,0,1,1,0,1,1},
        [6] = {1,0,1,1,1,1,1},
        [7] = {1,1,1,0,0,0,0},
        [8] = {1,1,1,1,1,1,1},
        [9] = {1,1,1,1,0,1,1}
    }
    local segs = segments[digit] or segments[0]
    if segs[1] == 1 then
        lcd.drawFilledRectangle(x + seg_thickness, y, seg_width, seg_thickness, color)
    end
    if segs[2] == 1 then
        lcd.drawFilledRectangle(x + seg_width + seg_thickness, y + seg_thickness, seg_thickness, seg_height, color)
    end
    if segs[3] == 1 then
        lcd.drawFilledRectangle(x + seg_width + seg_thickness, y + seg_height + seg_thickness * 2, seg_thickness, seg_height, color)
    end
    if segs[4] == 1 then
        lcd.drawFilledRectangle(x + seg_thickness, y + seg_height * 2 + seg_thickness * 2, seg_width, seg_thickness, color)
    end
    if segs[5] == 1 then
        lcd.drawFilledRectangle(x, y + seg_height + seg_thickness * 2, seg_thickness, seg_height, color)
    end
    if segs[6] == 1 then
        lcd.drawFilledRectangle(x, y + seg_thickness, seg_thickness, seg_height, color)
    end
    if segs[7] == 1 then
        lcd.drawFilledRectangle(x + seg_thickness, y + seg_height + seg_thickness, seg_width, seg_thickness, color)
    end
end
local function draw_time_display(x, y, hours, minutes, digit_size, color)
    local seg_width = digit_size * 0.6
    local seg_height = digit_size * 0.5
    local seg_thickness = digit_size * 0.15
    local digit_spacing = digit_size * 1.2
    local gray_color = lcd.RGB(80, 80, 80)
    local colon_size = seg_thickness * 1.5
    hours = math.max(0, math.min(23, hours))
    minutes = math.max(0, math.min(59, minutes))
    local current_x = x
    local hour_tens = math.floor(hours / 10)
    draw_digit_segment(current_x, y, hour_tens, seg_width, seg_height, seg_thickness, color, gray_color)
    current_x = current_x + digit_spacing
    local hour_ones = hours % 10
    draw_digit_segment(current_x, y, hour_ones, seg_width, seg_height, seg_thickness, color, gray_color)
    current_x = current_x + digit_spacing
    local colon_y1 = y + seg_height * 0.6
    local colon_y2 = y + seg_height * 1.4 + seg_thickness
    lcd.drawFilledRectangle(current_x - digit_spacing * 0.05, colon_y1, colon_size, colon_size, color)
    lcd.drawFilledRectangle(current_x - digit_spacing * 0.05, colon_y2, colon_size, colon_size, color)
    current_x = current_x + digit_spacing * 0.3
    local min_tens = math.floor(minutes / 10)
    draw_digit_segment(current_x, y, min_tens, seg_width, seg_height, seg_thickness, color, gray_color)
    current_x = current_x + digit_spacing
    local min_ones = minutes % 10
    draw_digit_segment(current_x, y, min_ones, seg_width, seg_height, seg_thickness, color, gray_color)
end
local function draw_ring_progress(xs, ys, value, max_value, size)
    local radius = size
    local ring_width = 8
    local segments = 20
    local gap = 3
    local angle_coverage = 270
    local segments_to_draw = 15
    local start_angle = -135
    local gray_color = lcd.RGB(80, 80, 80)
    value = math.max(0, math.min(max_value, value))
    local progress_percent = value / max_value
    local active_segments = math.floor(segments_to_draw * progress_percent)
    for i = 0, segments_to_draw - 1 do
        local angle_start = (360 / segments) * i + start_angle + gap / 2
        local angle_end = (360 / segments) * (i + 1) + start_angle - gap / 2
        local segment_color = gray_color
        if i < active_segments then
            local seg_percent = (i / (segments_to_draw - 1)) * 100
            local r = math.floor(seg_percent * 2.55)
            local g = math.floor(255 - (seg_percent * 2.55))
            local b = 0
            segment_color = lcd.RGB(r, g, b)
        end
        lcd.drawAnnulus(xs, ys, radius - ring_width, radius, angle_start, angle_end, segment_color)
    end
end
local function draw_power_gauge(center_x, center_y, radius, power_value, max_power, gauge_color, needle_color)
    local display_max = max_power or 5000
    power_value = math.max(0, math.min(display_max, power_value))
    local start_angle = 225
    local end_angle = 135
    local total_sweep = 270
    lcd.drawArc(center_x, center_y, radius, start_angle, 360, gauge_color)
    lcd.drawArc(center_x, center_y, radius - 2, start_angle, 360, gauge_color)
    lcd.drawArc(center_x, center_y, radius, 0, end_angle, gauge_color)
    lcd.drawArc(center_x, center_y, radius - 2, 0, end_angle, gauge_color)
    local num_ticks = 11
    for i = 0, num_ticks - 1 do
        local angle_deg = start_angle - (i * 27)
        local angle_rad = math.rad(angle_deg)
        local tick_start_r = radius - 5
        local tick_end_r = radius - 12
        local x1 = center_x + tick_start_r * math.cos(angle_rad)
        local y1 = center_y - tick_start_r * math.sin(angle_rad)
        local x2 = center_x + tick_end_r * math.cos(angle_rad)
        local y2 = center_y - tick_end_r * math.sin(angle_rad)
        lcd.drawLine(x1, y1, x2, y2, SOLID, gauge_color)
        if i % 2 == 0 then
            local value = (display_max / 10) * i
            local label = ""
            if value >= 1000 then
                label = string.format("%.0fk", value / 1000)
            else
                label = string.format("%.0f", value)
            end
            local text_r = radius - 22
            local text_x = center_x + text_r * math.cos(angle_rad)
            local text_y = center_y - text_r * math.sin(angle_rad)
            lcd.drawText(text_x, text_y, label, SMLSIZE + gauge_color + CENTER + VCENTER)
        end
    end
    local percentage = power_value / display_max
    local needle_angle_deg = start_angle - (percentage * total_sweep)
    local needle_angle_rad = math.rad(needle_angle_deg)
    local needle_length = radius - 15
    local needle_x = center_x + needle_length * math.cos(needle_angle_rad)
    local needle_y = center_y - needle_length * math.sin(needle_angle_rad)
    lcd.drawLine(center_x, center_y, needle_x, needle_y, SOLID, needle_color)
    lcd.drawLine(center_x + 1, center_y, needle_x + 1, needle_y, SOLID, needle_color)
    lcd.drawLine(center_x, center_y + 1, needle_x, needle_y + 1, SOLID, needle_color)
    lcd.drawFilledRectangle(center_x - 2, center_y - 2, 5, 5, needle_color)
    local power_str = ""
        power_str = string.format("%.0fA", power_value)
    lcd.drawText(center_x, center_y + 55, power_str,  needle_color + CENTER + VCENTER)
end
local function draw_model_list(model_list, selected_index, square_color, value_color)
    local screen_width = LCD_W
    local screen_height = LCD_H
    lcd.drawText(screen_width/2, 30, "SELECT MODEL",
                CENTER + VCENTER + DBLSIZE + square_color)
    if #model_list == 0 then
        lcd.drawText(screen_width/2, 150, "No models in index",
                    CENTER + VCENTER + value_color)
        lcd.drawText(screen_width/2, screen_height - 40,
                    "[EXIT] Back",
                    CENTER + VCENTER + SMLSIZE + square_color)
        return
    end
    local start_y = 100
    local line_height = 40
    local visible_count = 8
    local start_index = math.max(1, selected_index - 3)
    for i = start_index, math.min(start_index + visible_count - 1, #model_list) do
        local y = start_y + (i - start_index) * line_height
        local model = model_list[i]
        if i == selected_index then
            lcd.drawText(80, y, ">", BOLD + value_color)
        end
        lcd.drawText(120, y, model.name,
                    (i == selected_index) and (BOLD + value_color) or square_color)
        lcd.drawText(450, y, string.format("(%d flights)", model.log_count),
                    square_color)
    end
    lcd.drawText(screen_width/2, screen_height - 30,
                "[ENTER] Select  [EXIT] Back",
                CENTER + VCENTER + SMLSIZE + square_color)
end
local function draw_flight_log_list(model_name, log_data, fly_number,
                                   selected_index, square_color, value_color)
    local screen_width = LCD_W
    local screen_height = LCD_H
    lcd.drawText(screen_width/2, 50,
                string.format("FLIGHT LOGS - %s", model_name),
                CENTER + VCENTER + DBLSIZE + square_color)
    if fly_number == 0 then
        lcd.drawText(screen_width/2, 150, "No flight logs available",
                    CENTER + VCENTER + value_color)
        lcd.drawText(screen_width/2, screen_height - 40,
                    "[EXIT] Back",
                    CENTER + VCENTER + SMLSIZE + square_color)
        return
    end
    local start_y = 120
    local line_height = 35
    local visible_count = 8
    local start_index = math.max(1, selected_index - 3)
    for i = start_index, math.min(start_index + visible_count - 1, fly_number) do
        local y = start_y + (i - start_index) * line_height
        local log_line = log_data[i]
        if log_line and #log_line > 0 then
            local flight_num = string.sub(log_line, 1, 2)
            local time_str = string.sub(log_line, 4, 11)
            local duration = string.sub(log_line, 13, 17)
            if i == selected_index then
                lcd.drawText(80, y, ">", BOLD + value_color)
            end
            local info_str = string.format("#%s  %s  %s",
                                          flight_num, time_str, duration)
            lcd.drawText(110, y, info_str,
                        (i == selected_index) and (BOLD + value_color) or square_color)
        end
    end
    lcd.drawText(screen_width/2, screen_height - 40,
                "[ENTER] Details  [EXIT] Back",
                CENTER + VCENTER + SMLSIZE + square_color)
end
-- Curve recording feature is disabled - draw_rpm_chart
local function draw_rpm_chart(model_name, flight_num, square_color, value_color)
    local screen_width = LCD_W
    local screen_height = LCD_H
    -- Cache check: reuse directly for the same model and same flight number, avoid rereading the file
    local cache_key = model_name .. "|" .. tostring(flight_num)
    if chart_cache == nil or chart_cache_key ~= cache_key then
        chart_cache = {
            rpm_data     = load_rpm_data(model_name, flight_num),
            current_data = load_current_data(model_name, flight_num),
            voltage_data = load_voltage_data(model_name, flight_num),
        }
        chart_cache_key = cache_key
    end
    local rpm_data     = chart_cache.rpm_data
    local current_data = chart_cache.current_data
    local voltage_data = chart_cache.voltage_data
    lcd.drawText(screen_width/2, 20,
                string.format("Graph - Flight #%02d", flight_num),
                CENTER + VCENTER + DBLSIZE + square_color)
    if not rpm_data and not current_data and not voltage_data then
        lcd.drawText(screen_width/2, 150, "No data available",
                    CENTER + VCENTER + value_color)
        lcd.drawText(screen_width/2, screen_height - 30,
                    "[EXIT] Back",
                    CENTER + VCENTER + SMLSIZE + square_color)
        return
    end
    local start_time = (rpm_data and rpm_data.start_time) or (current_data and current_data.start_time) or (voltage_data and voltage_data.start_time) or "00:00:00"
    local end_time = (rpm_data and rpm_data.end_time) or (current_data and current_data.end_time) or (voltage_data and voltage_data.end_time) or "00:00:00"
    lcd.drawText(screen_width/2, 60,
                string.format("%s - %s", start_time, end_time),
                CENTER + VCENTER + square_color)
    local rpm_values = rpm_data and rpm_data.rpm_values or {}
    local current_values = current_data and current_data.current_values or {}
    local voltage_values = voltage_data and voltage_data.voltage_values or {}
    local data_count = math.max(#rpm_values, #current_values, #voltage_values)
    if data_count == 0 then
        lcd.drawText(screen_width/2, 150, "No data points",
                    CENTER + VCENTER + value_color)
        return
    end
    local max_rpm = 0
    local min_rpm = 99999
    if #rpm_values > 0 then
        for i = 1, #rpm_values do
            if rpm_values[i] > max_rpm then max_rpm = rpm_values[i] end
            if rpm_values[i] < min_rpm then min_rpm = rpm_values[i] end
        end
    end
    local max_current = 0
    local min_current = 99999
    if #current_values > 0 then
        for i = 1, #current_values do
            if current_values[i] > max_current then max_current = current_values[i] end
            if current_values[i] < min_current then min_current = current_values[i] end
        end
    end
    local max_voltage = 0
    local min_voltage = 99999
    if #voltage_values > 0 then
        for i = 1, #voltage_values do
            if voltage_values[i] > max_voltage then max_voltage = voltage_values[i] end
            if voltage_values[i] < min_voltage then min_voltage = voltage_values[i] end
        end
    end
    local y_axis_max_rpm = max_rpm + 200
    local y_axis_min_rpm = min_rpm
    local y_axis_range_rpm = y_axis_max_rpm - y_axis_min_rpm
    if y_axis_range_rpm == 0 then y_axis_range_rpm = 1 end
    local y_axis_max_current = max_current + 20
    local y_axis_min_current = min_current
    local y_axis_range_current = y_axis_max_current - y_axis_min_current
    if y_axis_range_current == 0 then y_axis_range_current = 1 end
    local y_axis_max_voltage = max_voltage + 2
    local y_axis_min_voltage = min_voltage - 2
    local y_axis_range_voltage = y_axis_max_voltage - y_axis_min_voltage
    if y_axis_range_voltage == 0 then y_axis_range_voltage = 1 end
    local chart_x = 80
    local chart_y = 100
    local chart_width = screen_width - 160
    local chart_height = 250
    lcd.drawRectangle(chart_x, chart_y, chart_width, chart_height, square_color)
    local y_tick_count = 5
    for i = 0, y_tick_count do
        local y = chart_y + (chart_height / y_tick_count) * i
        lcd.drawLine(chart_x, y, chart_x + chart_width, y, DOTTED, square_color)
        if #rpm_values > 0 then
            local y_value = y_axis_max_rpm - (y_axis_range_rpm / y_tick_count) * i
            lcd.drawText(chart_x - 5, y - 8, string.format("%d", y_value), RIGHT + SMLSIZE + GREEN)
        end
        if #current_values > 0 then
            local current_value = y_axis_max_current - (y_axis_range_current / y_tick_count) * i
            lcd.drawText(chart_x + chart_width + 5, y - 8, string.format("%.0f", current_value), SMLSIZE + RED)
        end
    end
    if #rpm_values > 1 then
        local x_step = chart_width / (data_count - 1)
        for i = 1, #rpm_values - 1, chart_render_step do
            local j = math.min(i + chart_render_step, #rpm_values)
            local x1 = chart_x + (i - 1) * x_step
            local y1 = chart_y + chart_height - ((rpm_values[i] - y_axis_min_rpm) / y_axis_range_rpm * chart_height)
            local x2 = chart_x + (j - 1) * x_step
            local y2 = chart_y + chart_height - ((rpm_values[j] - y_axis_min_rpm) / y_axis_range_rpm * chart_height)
            lcd.drawLine(x1, y1, x2, y2, SOLID, GREEN)
        end
    end
    if #current_values > 1 then
        local x_step = chart_width / (data_count - 1)
        for i = 1, #current_values - 1, chart_render_step do
            local j = math.min(i + chart_render_step, #current_values)
            local x1 = chart_x + (i - 1) * x_step
            local y1 = chart_y + chart_height - ((current_values[i] - y_axis_min_current) / y_axis_range_current * chart_height)
            local x2 = chart_x + (j - 1) * x_step
            local y2 = chart_y + chart_height - ((current_values[j] - y_axis_min_current) / y_axis_range_current * chart_height)
            lcd.drawLine(x1, y1, x2, y2, SOLID, RED)
        end
    end
    if #voltage_values > 1 then
        local x_step = chart_width / (data_count - 1)
        for i = 1, #voltage_values - 1, chart_render_step do
            local j = math.min(i + chart_render_step, #voltage_values)
            local x1 = chart_x + (i - 1) * x_step
            local y1 = chart_y + chart_height - ((voltage_values[i] - y_axis_min_voltage) / y_axis_range_voltage * chart_height)
            local x2 = chart_x + (j - 1) * x_step
            local y2 = chart_y + chart_height - ((voltage_values[j] - y_axis_min_voltage) / y_axis_range_voltage * chart_height)
            lcd.drawLine(x1, y1, x2, y2, SOLID, BLUE)
        end
    end
    local total_seconds = (data_count - 1) * 2
    for i = 0, data_count - 1 do
        if i % 15 == 0 or i == data_count - 1 then
            local x = chart_x + (chart_width / (data_count - 1)) * i
            local time_seconds = i * 2
            local time_min = math.floor(time_seconds / 60)
            local time_sec = math.floor(time_seconds % 60)
            lcd.drawLine(x, chart_y + chart_height, x, chart_y + chart_height + 6, SOLID, square_color)
            lcd.drawText(x, chart_y + chart_height + 8,
                        string.format("%d:%02d", time_min, time_sec),
                        CENTER + SMLSIZE + square_color)
        end
    end
    lcd.drawText(screen_width/2 - 180, chart_y + chart_height + 35,
                "RPM", SMLSIZE + GREEN)
    lcd.drawText(screen_width/2 - 80, chart_y + chart_height + 35,
                "Current(A)", SMLSIZE + RED)
    lcd.drawText(screen_width/2 + 70, chart_y + chart_height + 35,
                "Volt(V)", SMLSIZE + BLUE)
    -- Precision level indicator: show current step size, adjustable with up/down keys
    local detail_labels = { "1-Max", "2-High", "3-Mid", "4-Low", "5-Min" }
   
    --lcd.drawText(screen_width - 10, chart_y + chart_height + 35,
      --          string.format("Detail:%s", detail_labels[chart_render_step]),
        --        RIGHT + SMLSIZE + square_color)
    lcd.drawText(screen_width/2, screen_height - 30,
                "[UP/DN] Detail  [EXIT] Back",
                CENTER + VCENTER + SMLSIZE + square_color)
end

local function draw_digital_display(x, y, value, num_digits, decimal_places, digit_size, color)
    local seg_width = digit_size * 0.6
    local seg_height = digit_size * 0.5
    local seg_thickness = digit_size * 0.15
    local digit_spacing = digit_size * 1.2
    local gray_color = lcd.RGB(80, 80, 80)
    local dot_size = seg_thickness
    local multiplier = math.pow(10, decimal_places)
    local int_part = math.floor(value)
    local dec_part = math.floor((value - int_part) * multiplier + 0.5)
    if dec_part >= multiplier then
        int_part = int_part + 1
        dec_part = 0
    end
    local max_int_value = math.pow(10, num_digits) - 1
    int_part = math.min(max_int_value, int_part)
    local int_value_digits = 0
    if int_part == 0 then
        int_value_digits = 1
    else
        int_value_digits = math.floor(math.log(int_part) / math.log(10)) + 1
    end
    local current_x = x
    for i = 0, num_digits - 1 do
        local divisor = math.pow(10, num_digits - 1 - i)
        local digit = math.floor(int_part / divisor) % 10
        local digit_color = gray_color
        local is_leading_zero = true
        if i >= (num_digits - int_value_digits) then
            digit_color = color
            is_leading_zero = false
        end
        draw_digit_segment(current_x, y, digit, seg_width, seg_height, seg_thickness, digit_color, gray_color)
        current_x = current_x + digit_spacing
    end
    if decimal_places > 0 then
        local dot_y = y + seg_height * 2 + seg_thickness * 2
        lcd.drawFilledRectangle(current_x - digit_spacing * 0.15, dot_y, dot_size, dot_size, color)
    end
    for i = 0, decimal_places - 1 do
        local divisor = math.pow(10, decimal_places - 1 - i)
        local digit = math.floor(dec_part / divisor) % 10
        draw_digit_segment(current_x, y, digit, seg_width, seg_height, seg_thickness, color, gray_color)
        current_x = current_x + digit_spacing
    end
end
local function draw_flight_report_popup(xs, ys, data, value_color, square_color)
    local popup_width = 600
    local popup_height = 280
    local popup_x = xs - popup_width / 2
    local popup_y = ys - popup_height / 2
    lcd.drawFilledRectangle(popup_x, popup_y, popup_width, popup_height, BLACK)
    draw_rounded_rectangle(popup_x, popup_y, popup_width, popup_height, 10, value_color)
    lcd.drawFilledRectangle(popup_x + 3, popup_y + 3, popup_width - 6, 2, value_color)
    lcd.drawFilledRectangle(popup_x + 3, popup_y + popup_height - 5, popup_width - 6, 2, value_color)
    lcd.drawText(popup_x + popup_width / 2, popup_y + 30, "Flight Report", CENTER + VCENTER + DBLSIZE + value_color)
    local col1_x = popup_x + 30
    lcd.drawText(col1_x, popup_y + 80, "Model:", square_color)
    lcd.drawText(col1_x, popup_y + 120, "Flight Time:", square_color)
    lcd.drawText(col1_x, popup_y + 160, "Max Power:", square_color)
    lcd.drawText(col1_x, popup_y + 200, "Max Current:", square_color)
    local col2_x = popup_x + 200
    lcd.drawText(col2_x, popup_y + 80, data.model_name, BOLD + square_color)
    lcd.drawText(col2_x, popup_y + 120, data.flight_time, BOLD + square_color)
    local power_str = string.format("%dW", data.max_power)
    if data.max_power >= 1000 then
        power_str = string.format("%.1fkW", data.max_power / 1000)
    end
    lcd.drawText(col2_x, popup_y + 160, power_str, BOLD + square_color)
    lcd.drawText(col2_x, popup_y + 200, string.format("%.1fA", data.max_current), BOLD + square_color)
    local col3_x = popup_x + 400
    local button_width = 160
    local button_height = 40
    local button_spacing = 15
    local btn1_y = popup_y + 75
    draw_rounded_rectangle(col3_x, btn1_y, button_width, button_height, 5, value_color)
    lcd.drawText(col3_x + button_width / 2, btn1_y + button_height / 2, "Close", CENTER + VCENTER + square_color)
    local btn2_y = btn1_y + button_height + button_spacing
    draw_rounded_rectangle(col3_x, btn2_y, button_width, button_height, 5, value_color)
    lcd.drawText(col3_x + button_width / 2, btn2_y + button_height / 2, "Current Log", CENTER + VCENTER + SMLSIZE + square_color)
    return {
        popup_x = popup_x,
        popup_y = popup_y,
        popup_width = popup_width,
        popup_height = popup_height,
        col3_x = col3_x,
        button_width = button_width,
        button_height = button_height,
        btn1_y = btn1_y,
        btn2_y = btn2_y
    }
end
local function draw_log_content(xs, ys, title, message, flags)
    local extract = {}
    local value
    local index, length = 4, 8
    extract[1] = string.sub(message, index, index + length - 1)
    index = 13
    length = 5
    extract[2] = string.sub(message, index, index + length - 1)
    for t = 1, 20 do
        index = index + length + 1
        if t == 2 or t == 16 or t == 17 or t == 18 then
            length = 3
        elseif t == 4 or t == 5 then
            length = 5
        else
            length = 4
        end
        value = tonumber(string.sub(message, index, index + length - 1))
        if t == 4 or t == 6 or t == 7 or t == 19 or t == 20 then
            extract[t + 2] = string.format("%.1f", value)
        else
            extract[t + 2] = string.format("%d", value)
        end
    end
    local width = 480
    local height = 300
    draw_rounded_rectangle(xs, ys, width, height, 8, flags)
    lcd.drawFilledRectangle(xs + 3, ys + 3, width - 6, 30, flags)
    lcd.drawText(xs + width / 2, ys + 18, title, CENTER + VCENTER + BOLD + BLACK)
    lcd.drawText(xs + 15, ys + 45, "Flight Time", BOLD + flags)
    lcd.drawText(xs + 140, ys + 48,extract[2] ,  flags)
    lcd.drawLine(xs + 20, ys + 80, xs + width - 10, ys + 80, SOLID, flags)
    local left_x = xs + 15
    local section_y = ys + 95
    lcd.drawText(left_x, section_y, "POWER", BOLD + flags)
    section_y = section_y + 25
    lcd.drawText(left_x, section_y, "Capacity", SMLSIZE + flags)
    lcd.drawText(left_x + 110, section_y, extract[3] .. " mAh", flags)
    section_y = section_y + 22
    lcd.drawText(left_x, section_y, "Fuel", SMLSIZE + flags)
    lcd.drawText(left_x + 110, section_y, extract[4] .. "%", flags)
    local fuel_percent = tonumber(extract[4]) or 0
    local bar_width = 80
    local bar_height = 6
    local fill_width = math.floor(bar_width * fuel_percent / 100)
    if fill_width > 0 then
        lcd.drawFilledRectangle(left_x + 152, section_y + 5, fill_width - 4, bar_height - 4, flags)
    end
    section_y = section_y + 25
    lcd.drawText(left_x, section_y, "Current", SMLSIZE + flags)
    lcd.drawText(left_x + 110, section_y, extract[6] .. " A", flags)
    section_y = section_y + 22
    lcd.drawText(left_x, section_y, "Power", SMLSIZE + flags)
    local power_val = tonumber(extract[7]) or 0
    local power_str = power_val >= 1000 and string.format("%.1f kW", power_val / 1000) or extract[7] .. " W"
    lcd.drawText(left_x + 110, section_y, power_str, flags)
    section_y = section_y + 25
    lcd.drawText(left_x, section_y, "Head Speed", SMLSIZE + flags)
    lcd.drawText(left_x + 110, section_y, extract[5] .. " rpm", flags)
    section_y = section_y + 22
    lcd.drawText(left_x, section_y, "Throttle", SMLSIZE + flags)
    lcd.drawText(left_x + 110, section_y, extract[20] .. "%", flags)
    local mid_x = xs + width / 2
    lcd.drawLine(mid_x, ys + 85, mid_x, ys + height - 10, SOLID, flags)
    local right_x = mid_x + 15
    section_y = ys + 95
    lcd.drawText(right_x, section_y, "VOLTAGE", BOLD + flags)
    section_y = section_y + 25
    lcd.drawText(right_x, section_y, "Battery", SMLSIZE + flags)
    lcd.drawText(right_x + 70, section_y, extract[8] .. "V", flags)
    lcd.drawText(right_x + 130, section_y, ">", SMLSIZE + flags)
    lcd.drawText(right_x + 145, section_y, extract[9] .. "V", flags)
    section_y = section_y + 22
    lcd.drawText(right_x, section_y, "BEC", SMLSIZE + flags)
    lcd.drawText(right_x + 70, section_y, extract[22] .. "V", flags)
    lcd.drawText(right_x + 130, section_y, ">", SMLSIZE + flags)
    lcd.drawText(right_x + 145, section_y, extract[21] .. "V", flags)
    section_y = section_y + 30
    lcd.drawText(right_x, section_y, "TEMPERATURE", BOLD + flags)
    section_y = section_y + 25
    lcd.drawText(right_x, section_y, "ESC", SMLSIZE + flags)
    lcd.drawText(right_x + 70, section_y, extract[11] .. "°C", flags)
    lcd.drawText(right_x + 130, section_y, ">", SMLSIZE + flags)
    lcd.drawText(right_x + 145, section_y, extract[10] .. "°C", flags)
    section_y = section_y + 22
    lcd.drawText(right_x, section_y, "MCU", SMLSIZE + flags)
    lcd.drawText(right_x + 70, section_y, extract[13] .. "°C", flags)
    lcd.drawText(right_x + 130, section_y, ">", SMLSIZE + flags)
    lcd.drawText(right_x + 145, section_y, extract[12] .. "°C", flags)
    section_y = section_y + 30
end
local function refresh(widget, event, touchState)
    local screen_width =  LCD_W or widget.zone.w
    local screen_height =  LCD_H or widget.zone.h
    if not signal_lost then
        if event == nil then
        elseif event ~= 0 then
            if event == EVT_VIRTUAL_NEXT_PAGE then
                if display_mode == 0 then
                    display_mode = 1
                    local rqly_percent = (field_id[10][2] and value_min_max[10][1]) or 0
                    local has_signal = (rqly_percent > 0 and telemetry_initialized)
                    if has_signal then
                        log_view_mode = 1
                        viewing_model_name = cached_model_name
                        viewing_log_data = log_data
                        viewing_fly_number = fly_number
                        sele_number = math.min(sele_number, fly_number)
                        if sele_number == 0 then sele_number = 1 end
                    else
                        log_view_mode = 0
                        model_list = scan_model_logs()
                        selected_model_index = 1
                    end
                    display_log_flag = false
                    playTone(200, 100, 100, PLAY_NOW)
                else
                end
        elseif event == EVT_VIRTUAL_PREV_PAGE then
            if display_mode == 0 then
            elseif display_mode == 1 then
                display_mode = 0
                log_view_mode = 0
                playTone(200, 100, 100, PLAY_NOW)
            elseif display_mode == 2 then
                display_mode = 1
                display_log_flag = false
                playTone(200, 100, 100, PLAY_NOW)
            end
        elseif event == EVT_VIRTUAL_NEXT then
            if display_mode == 1 then
                if log_view_mode == 0 then
                    if #model_list > 0 then
                        if selected_model_index < #model_list then
                            selected_model_index = selected_model_index + 1
                        else
                            selected_model_index = 1
                        end
                        playTone(200, 50, 100, PLAY_NOW)
                    end
                elseif log_view_mode == 1 then
                    if viewing_fly_number > 0 then
                        if sele_number < viewing_fly_number then
                            sele_number = sele_number + 1
                        else
                            sele_number = 1
                        end
                        playTone(200, 50, 100, PLAY_NOW)
                    end
                elseif log_view_mode == 3 then
                    -- Chart page: reduce precision (step +1, max 5) to reduce drawLine calls
                    if chart_render_step < 5 then
                        chart_render_step = chart_render_step + 1
                        playTone(200, 50, 50, PLAY_NOW)
                    end
                end
            end
        elseif event == EVT_VIRTUAL_PREV then
            if display_mode == 1 then
                if log_view_mode == 0 then
                    if #model_list > 0 then
                        if selected_model_index > 1 then
                            selected_model_index = selected_model_index - 1
                        else
                            selected_model_index = #model_list
                        end
                        playTone(200, 50, 100, PLAY_NOW)
                    end
                elseif log_view_mode == 1 then
                    if viewing_fly_number > 0 then
                        if sele_number > 1 then
                            sele_number = sele_number - 1
                        else
                            sele_number = viewing_fly_number
                        end
                        playTone(200, 50, 100, PLAY_NOW)
                    end
                elseif log_view_mode == 3 then
                    -- Chart page: increase precision (step -1, min 1)
                    chart_render_step = 2
                 --   if chart_render_step > 1 then
                   --     chart_render_step = chart_render_step - 1
                     --   playTone(200, 50, 50, PLAY_NOW)
                  --  end
                end
            end
        elseif event == EVT_VIRTUAL_ENTER then
            if display_mode == 1 then
                if log_view_mode == 0 then
                    if #model_list > 0 then
                        viewing_model_name = model_list[selected_model_index].name
                        local result = load_model_logs(viewing_model_name)
                        viewing_log_data = result.log_data
                        viewing_fly_number = result.fly_number
                        sele_number = 1
                        log_view_mode = 1
                        playTone(100, 200, 100, PLAY_NOW, 10)
                    end
                elseif log_view_mode == 1 then
                    if viewing_fly_number > 0 and sele_number > 0 and
                       sele_number <= viewing_fly_number and viewing_log_data[sele_number] then
                        log_view_mode = 2
                        playTone(100, 200, 100, PLAY_NOW, 10)
                    else
                        playTone(3000, 100, 50, PLAY_NOW)
                    end
                elseif log_view_mode == 2 then
                    -- Curve recording feature is disabled - no longer enter chart view
                    
                    log_view_mode = 3
                    playTone(100, 200, 100, PLAY_NOW, 10)
                    
                    playTone(600, 50, 50, PLAY_NOW)
                elseif log_view_mode == 3 then
                    playTone(600, 50, 50, PLAY_NOW)
                end
            else
                playTone(600, 50, 50, PLAY_NOW)
            end
        elseif event == EVT_VIRTUAL_EXIT then
            if display_mode == 1 then
                if log_view_mode == 0 then
                    display_mode = 0
                    log_view_mode = 0
                    playTone(10000, 200, 100, PLAY_NOW, -60)
                elseif log_view_mode == 1 then
                    local rqly_percent = (field_id[10][2] and value_min_max[10][1]) or 0
                    local has_signal = (rqly_percent > 0 and telemetry_initialized)
                    if has_signal or viewing_model_name == cached_model_name then
                        display_mode = 0
                        log_view_mode = 0
                    else
                        log_view_mode = 0
                    end
                    playTone(10000, 200, 100, PLAY_NOW, -60)
                elseif log_view_mode == 2 then
                    log_view_mode = 1
                    playTone(10000, 200, 100, PLAY_NOW, -60)
                elseif log_view_mode == 3 then
                    log_view_mode = 2
                    chart_cache = nil
                    chart_cache_key = ""
                    playTone(10000, 200, 100, PLAY_NOW, -60)
                end
            else
                display_mode = 0
                display_log_flag = false
                playTone(10000, 200, 100, PLAY_NOW, -60)
            end
        end
        end
    else
        if event ~= nil and event ~= 0 then
            if event == EVT_VIRTUAL_ENTER or event == EVT_VIRTUAL_EXIT then
                signal_lost = false
                popup_button_positions = nil
                playTone(200, 100, 100, PLAY_NOW)
            elseif touchState then
                if popup_button_positions then
                    local pos = popup_button_positions
                    if touchState.x >= pos.col3_x and touchState.x <= (pos.col3_x + pos.button_width) and
                       touchState.y >= pos.btn1_y and touchState.y <= (pos.btn1_y + pos.button_height) then
                        signal_lost = false
                        popup_button_positions = nil
                        playTone(200, 100, 100, PLAY_NOW)
                    elseif touchState.x >= pos.col3_x and touchState.x <= (pos.col3_x + pos.button_width) and
                           touchState.y >= pos.btn2_y and touchState.y <= (pos.btn2_y + pos.button_height) then
                        signal_lost = false
                        popup_button_positions = nil
                        if write_en_flag and second[1] > 30 then
                            goto_log_after_write = true
                        elseif fly_number > 0 and log_data[fly_number] then
                            display_mode = 1
                            log_view_mode = 2
                            viewing_model_name = cached_model_name
                            viewing_log_data = log_data
                            viewing_fly_number = fly_number
                            sele_number = fly_number
                        else
                            display_mode = 1
                            log_view_mode = 1
                            viewing_model_name = cached_model_name
                            viewing_log_data = log_data
                            viewing_fly_number = fly_number
                            sele_number = 1
                        end
                        playTone(200, 100, 100, PLAY_NOW)
                    else
                        signal_lost = false
                        popup_button_positions = nil
                        playTone(100, 50, 50, PLAY_NOW)
                    end
                end
            end
        end
    end
    lcd.setColor(CUSTOM_COLOR, BLACK)
    local bg_color = lcd.getColor(CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, widget.options.SquareColor)
    local square_color = lcd.getColor(CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, widget.options.ValueColor)
    local value_color = lcd.getColor(CUSTOM_COLOR)
    if LED_STRIP_LENGTH and LED_STRIP_LENGTH > 0 then
        if widget.options.DispLED == 1 then
            local start_color = widget.options.SquareColor
            local end_color = widget.options.ValueColor
            if led_cache.last_start_color ~= start_color or led_cache.last_end_color ~= end_color then
                led_cache.last_start_color = start_color
                led_cache.last_end_color = end_color
                local start_rgb565 = math.floor(start_color / 65536)
                local start_red = math.floor(start_rgb565 / 2048) * 8
                local start_green = (math.floor(start_rgb565 / 32) % 64) * 4
                local start_blue = (start_rgb565 % 32) * 8
                local end_rgb565 = math.floor(end_color / 65536)
                local end_red = math.floor(end_rgb565 / 2048) * 8
                local end_green = (math.floor(end_rgb565 / 32) % 64) * 4
                local end_blue = (end_rgb565 % 32) * 8
                for i = 0, LED_STRIP_LENGTH - 1 do
                    local ratio = 0.5
                    local ratio = (i % 2) / 1
                    local red = start_red + (end_red - start_red) * ratio
                    local green = start_green + (end_green - start_green) * ratio
                    local blue = start_blue + (end_blue - start_blue) * ratio
                    setRGBLedColor(i, math.floor(red), math.floor(green), math.floor(blue))
                end
                applyRGBLedColors()
            end
        else
            if led_cache.last_start_color ~= 0 or led_cache.last_end_color ~= 0 then
                led_cache.last_start_color = 0
                led_cache.last_end_color = 0
                for i = 0, LED_STRIP_LENGTH - 1 do
                    setRGBLedColor(i, 0, 0, 0)
                end
                applyRGBLedColors()
            end
        end
    end
    lcd.drawFilledRectangle(0, 0, screen_width, screen_height, bg_color)
    if not bg_pic_obj then
        bg_pic_obj = Bitmap.open(IMAGE_ROOT .. "/background.png")
    end
    if bg_pic_obj then
        lcd.drawBitmap(bg_pic_obj, 0, 0)
    end
    local title_height = 25
    local model_name = model.getInfo().name
    local current_time = getDateTime()
    local time_str = string.format("%02d:%02d:%02d", current_time.hour, current_time.min, current_time.sec)
    lcd.drawText(630, 390,  widget.options.UserName, MIDSIZE + square_color)
    lcd.drawText(500, 436, model_name, MIDSIZE + value_color)
    if tg_pic_obj then
           lcd.drawBitmap(tg_pic_obj, 530, 190)        
    else
        if default_pic_obj then
            lcd.drawBitmap(default_pic_obj, 530, 190)
        end
    end
    local tx_voltage = getValue("tx-voltage") or getValue("TxBt") or 0
    local tx_battery_str = string.format("%.1fV", tx_voltage)
    local tx_color = value_color
    if tx_voltage < 6.5 then
        tx_color = RED
    elseif tx_voltage >= 6.5 and tx_voltage <= 7.0 then
        tx_color = YELLOW
    end
    lcd.drawText(682, 14, "Tx ", BOLD + square_color)
    lcd.drawText(714, 14, tx_battery_str, BOLD + tx_color)
    lcd.drawText(316, 50, "RSSI" , CENTER + VCENTER + square_color)
    local rqly_percent = (field_id[10][2] and value_min_max[10][1]) or 0
    rqly_signal_bars_ladder(344, 60, rqly_percent, lcd.RGB(80, 80, 80), 1.0)
    if rqly_percent > 0 then
        lcd.drawText(430, 50, string.format("%ddB", rqly_percent), CENTER + VCENTER  + value_color)
    else
        lcd.drawText(425, 50, "---", CENTER + VCENTER + MIDSIZE + RED)
    end
    local has_telemetry = false
    if field_id[10][2] then
        if rqly_percent > 0 then
            has_telemetry = true
        end
    end
    if has_telemetry == true and telemetry_initialized == false then
        telemetry_initialized = true
        last_rqly_status = true
    end
    if telemetry_initialized == true then
        if has_telemetry == false and last_rqly_status == true then
            signal_lost = ENABLE_FLIGHT_REPORT_POPUP
            last_rqly_status = false
            signal_lost_data.model_name = cached_model_name
            signal_lost_data.flight_time = string.format("%02d:%02d", math.floor(second[1] % 3600 / 60), second[1] % 3600 % 60)
            signal_lost_data.max_power = power_max[1]
            signal_lost_data.max_current = value_min_max[2][2]
            if ENABLE_FLIGHT_REPORT_POPUP then
                playTone(2000, 300, 100, PLAY_NOW)
            end
        elseif has_telemetry == true then
            last_rqly_status = true
            signal_lost = false
        end
    end
    local current_model_name = model.getInfo().name
    local should_load_log = false
    if rqly_percent > 0 and not telemetry_initialized and display_mode ~= 1 then
        telemetry_initialized = true
        should_load_log = true
    end
    if current_model_name ~= cached_model_name and current_model_name ~= "" and display_mode ~= 1 then
        cached_model_name = current_model_name
        cached_pic_path = MODEL_IMAGE_ROOT .. "/" .. string.sub(cached_model_name, 2) .. ".png"
        should_load_log = true
    end
    if should_load_log and current_model_name and current_model_name ~= "" then
        local safe_model_name = string.gsub(current_model_name, "[<>:\"/\\|?*]", "")
        local new_file_name = "[".. safe_model_name .."]" ..
            string.format("%d", getDateTime().year) ..
            string.format("%02d", getDateTime().mon) ..
            string.format("%02d", getDateTime().day) .. ".log"
        local new_file_path = LOG_ROOT .. "/" .. new_file_name
        if fstat(cached_pic_path) then
            tg_pic_obj = Bitmap.open(cached_pic_path)
        else
            tg_pic_obj = nil
        end
        file_name = new_file_name
        file_path = new_file_path
        log_data = {}
        local file_info = fstat(file_path)
        local read_count = 1
        if file_info ~= nil and file_info.size > 0 then
            local temp_file_obj = io.open(file_path, "r")
            if temp_file_obj then
                log_info = io.read(temp_file_obj, LOG_INFO_LEN + 1)
                while true do
                    log_data[read_count] = io.read(temp_file_obj, LOG_DATA_LEN + 1)
                    if #log_data[read_count] == 0 then
                        break
                    else
                        read_count = read_count + 1
                    end
                end
                io.close(temp_file_obj)
                if log_info and string.len(log_info) >= 23 then
                    hours = string.sub(log_info, 12, 13)
                    minutes[2] = string.sub(log_info, 15, 16)
                    seconds[2] = string.sub(log_info, 18, 19)
                    total_second = tonumber(string.sub(log_info, 12, 13)) * 3600
                    total_second = total_second + tonumber(string.sub(log_info, 15, 16)) * 60
                    total_second = total_second + tonumber(string.sub(log_info, 18, 19))
                    local str_temp = string.sub(log_info, 21, 23)
                    if tonumber(str_temp) ~= nil then
                        fly_number = tonumber(str_temp)
                    end
                end
            end
        else
            fly_number = 0
            log_info = string.format("%d", getDateTime().year) .. '/' ..
                string.format("%02d", getDateTime().mon) .. '/' ..
                string.format("%02d", getDateTime().day) .. '|' ..
                "00:00:00" .. '|' ..
                "00\n"
        end
        session_flight_count = 0
    end
    bank_info.current = (field_id[17][2] and value_min_max[17][1]) or 1
    local bank_color = square_color  
    if bank_info.current == 1 then
        bank_color = lcd.RGB(0, 100, 255)      
    elseif bank_info.current == 2 then
        bank_color = lcd.RGB(255, 165, 0)      
    elseif bank_info.current == 3 then
        bank_color = lcd.RGB(255, 255, 0)      
    end
    lcd.drawText(175, 44, tostring(bank_info.current), CENTER + VCENTER + BOLD + MIDSIZE + bank_color)
    local arm_status = (field_id[13][2] and value_min_max[13][1]) or 0
    local gov_status = (field_id[14][2] and value_min_max[14][1]) or 0
    local is_armed = false
    if field_id[13][2] then
        is_armed = (arm_status == 1 or arm_status == 3)
        if arm_status == 2 and last_arm_status ~= 2 and second[1] > 30 then
            session_flight_count = session_flight_count + 1
        end
        if is_armed and (last_arm_status == 0 or last_arm_status == 2) then
            current_flight_max_current = 0
        end
        last_arm_status = arm_status
    end
    local gov_state_names = { "OFF", "IDLE", "SPOOLUP", "RECOVERY", "ACTIVE", "THR-OFF", "LOST-HS", "AUTOROT", "BAILOUT" }
    if is_armed then
        lcd.drawText(500,52, "GOV:", CENTER + VCENTER + square_color) 
        if field_id[14][2] then
            local gov_name = gov_state_names[gov_status + 1] or "UNK"
            if gov_name == "SPOOLUP" then
                lcd.drawText(582, 53, gov_name,BOLD+ CENTER + VCENTER +  value_color)
            else
                lcd.drawText(548, 53, gov_name,BOLD+ CENTER + VCENTER +  value_color)
            end
        else
            lcd.drawText(582, 53, "ARMED", BOLD+CENTER + VCENTER +  GREEN)
        end
    else
        lcd.drawText(500, 52, "ARM:", CENTER + VCENTER + square_color)
        if field_id[13][2] then
            lcd.drawText(582, 54, "DISARMED", BOLD+CENTER + VCENTER +   RED)
        else
            lcd.drawText(582, 54, "NO TELE", BOLD+ CENTER + VCENTER +   BLINK + RED)
        end
    end
    local hold_active = false
    if widget.options.HoldSwitch ~= 0 then
        local switch_value = getSwitchValue(widget.options.HoldSwitch)
        if switch_value and switch_value ~= 0 and switch_value ~= false then
            hold_active = true
        else
            hold_active = false
        end
    end
    if hold_active then
        if hold1_pic_obj then
            lcd.drawBitmap(hold1_pic_obj, 90, 25)
        end
    else
        if hold2_pic_obj then
            lcd.drawBitmap(hold2_pic_obj, 90, 25)
        end
    end
    for k = 1, TELE_ITEMS do
        if field_id[k][2] then
            local get_value = getValue(field_id[k][1])
            value_min_max[k][1] = get_value  
            if not hold_active then
                if get_value > value_min_max[k][2] then
                    value_min_max[k][2] = get_value
                elseif get_value < value_min_max[k][3] then
                    value_min_max[k][3] = get_value
                end
            end
        end
    end
    if is_armed then
        if arm_flag == false then
            arm_flag = true
            for s = 1, TELE_ITEMS do
                if field_id[s][2] then
                    value_min_max[s][2] = value_min_max[s][1]
                    value_min_max[s][3] = value_min_max[s][1]
                end
            end
            second[1] = 0
            power_max[1] = 0
            power_max[2] = 0
            write_en_flag = false
            -- Curve recording feature is disabled - initialize data buffers
            
            rpm_buffer = {}
            rpm_collect_timer = 0
            rpm_start_time = string.format("%02d:%02d:%02d",
                getDateTime().hour,
                getDateTime().min,
                getDateTime().sec)
            current_buffer = {}
            current_start_time = rpm_start_time
            voltage_buffer = {}
            voltage_start_time = rpm_start_time
            
        end
    else
        if arm_flag then
            arm_flag = false
            write_en_flag = true
        end
    end
    power_max[2] = math.min(math.floor(value_min_max[1][1] * value_min_max[2][1]), 99999)
    if power_max[1] < power_max[2] then
        power_max[1] = power_max[2]
    end
    second[3] = getRtcTime()
    if second[2] ~= second[3] then
        second[2] = second[3]
        if arm_flag then
            second[1] = second[1] + 1
            total_second = total_second + 1
            -- Curve recording feature is disabled - data collection
            
            rpm_collect_timer = rpm_collect_timer + 1
            if rpm_collect_timer >= rpm_collect_interval then
                rpm_collect_timer = 0
                local current_rpm = (field_id[3][2] and value_min_max[3][1]) or 0
                if #rpm_buffer < 300 then table.insert(rpm_buffer, current_rpm) end
                local current_value = (field_id[2][2] and value_min_max[2][1]) or 0
                if #current_buffer < 300 then table.insert(current_buffer, current_value) end
                local voltage_value = (field_id[1][2] and value_min_max[1][1]) or 0
                if #voltage_buffer < 300 then table.insert(voltage_buffer, voltage_value) end
            end
            
        end
    end
    minutes[1] = string.format("%02d", math.floor(second[1] % 3600 / 60))
    seconds[1] = string.format("%02d", second[1] % 3600 % 60)
    hours = string.format("%02d", math.floor(total_second / 3600))
    minutes[2] = string.format("%02d", math.floor(total_second % 3600 / 60))
    seconds[2] = string.format("%02d", total_second % 3600 % 60)
    if write_en_flag and fly_number < 57 and second[1] > 30 then
        -- Current frame: prepare data only, do not perform any file I/O
        fly_number = fly_number + 1
        local end_time_str = string.format("%02d:%02d:%02d",
            getDateTime().hour, getDateTime().min, getDateTime().sec)
        log_info =
            string.format("%d", getDateTime().year) .. '/' ..
            string.format("%02d", getDateTime().mon) .. '/' ..
            string.format("%02d", getDateTime().day) .. '|' ..
            hours .. ':' .. minutes[2] .. ':' .. seconds[2] .. '|' ..
            string.format("%02d", fly_number) .. "\n"
        log_data[fly_number] =
            string.format("%02d", fly_number) .. '|' ..
            string.format("%02d", getDateTime().hour) .. ':' ..
            string.format("%02d", getDateTime().min) .. ':' ..
            string.format("%02d", getDateTime().sec) .. '|' ..
            minutes[1] .. ':' .. seconds[1] .. '|' ..
            string.format("%04d", math.max(0, value_min_max[4][1] - value_min_max[4][3])) .. '|' ..
            string.format("%03d", math.max(0, value_min_max[5][2] - value_min_max[5][1])) .. '|' ..
            string.format("%04d", value_min_max[3][2]) .. '|' ..
            string.format("%05.1f", value_min_max[2][2]) .. '|' ..
            string.format("%05d", power_max[1]) .. '|' ..
            string.format("%04.1f", value_min_max[1][2]) .. '|' ..
            string.format("%04.1f", value_min_max[1][3]) .. '|' ..
            string.format("%+04d", value_min_max[6][2]) .. '|' ..
            string.format("%+04d", value_min_max[6][3]) .. '|' ..
            string.format("%+04d", value_min_max[7][2]) .. '|' ..
            string.format("%+04d", value_min_max[7][3]) .. "|" ..
            string.format("%+04d", value_min_max[8][2]) .. '|' ..
            string.format("%+04d", value_min_max[8][3]) .. '|' ..
            string.format("%+04d", value_min_max[9][2]) .. '|' ..
            string.format("%+04d", value_min_max[9][3]) .. '|' ..
            string.format("%03d", value_min_max[10][2]) .. '|' ..
            string.format("%03d", value_min_max[10][3]) .. '|' ..
            string.format("%03d", value_min_max[11][2]) .. '|' ..
            string.format("%04.1f", value_min_max[12][2]) .. '|' ..
            string.format("%04.1f", value_min_max[12][3]) .. "\n"
        -- Snapshot: store all data needed for writing and release buffer references (new empty tables for the next flight)
        write_snapshot = {
            file_path  = file_path,
            log_info   = log_info,
            log_data   = log_data,
            fly_number = fly_number,
            model_name = cached_model_name,
            end_time   = end_time_str,
            rpm_buf    = rpm_buffer,   rpm_start = rpm_start_time,
            cur_buf    = current_buffer, cur_start = current_start_time,
            volt_buf   = voltage_buffer, volt_start = voltage_start_time,
        }
        write_state = 1
        write_en_flag = false
        rpm_buffer = {};  current_buffer = {};  voltage_buffer = {}
        -- Finalization work without heavy I/O runs in the trigger frame
        update_model_index(cached_model_name)
        session_flight_count = 0
        local current_model_name = model.getInfo().name
        if current_model_name and current_model_name ~= "" then
            increment_total_flight_count(current_model_name)
        end
        if goto_log_after_write then
            goto_log_after_write = false
            display_mode = 1
            log_view_mode = 2
            viewing_model_name = cached_model_name
            viewing_log_data = log_data
            viewing_fly_number = fly_number
            sele_number = fly_number
        end
    end
    -- Multi-frame write state machine: complete only one file write per frame to avoid exceeding the CPU budget in a single frame
    if write_state == 1 and write_snapshot then
        -- Frame 1: write the main log file (use table.concat to write historical entries in one shot)
        local f = io.open(write_snapshot.file_path, "w")
        if f then
            io.write(f, write_snapshot.log_info)
            if write_snapshot.fly_number > 1 then
                io.write(f, table.concat(write_snapshot.log_data, "", 1, write_snapshot.fly_number - 1))
            end
            io.write(f, write_snapshot.log_data[write_snapshot.fly_number])
            io.close(f)
        end
        write_state = 2
    elseif write_state == 2 and write_snapshot then
        -- Frame 2: write the RPM curve file
        if #write_snapshot.rpm_buf > 0 then
            write_rpm_data(write_snapshot.model_name, write_snapshot.fly_number,
                write_snapshot.rpm_start, write_snapshot.end_time, write_snapshot.rpm_buf)
        end
        write_state = 3
    elseif write_state == 3 and write_snapshot then
        -- Frame 3: write the current curve file
        if #write_snapshot.cur_buf > 0 then
            write_current_data(write_snapshot.model_name, write_snapshot.fly_number,
                write_snapshot.cur_start, write_snapshot.end_time, write_snapshot.cur_buf)
        end
        write_state = 4
    elseif write_state == 4 and write_snapshot then
        -- Frame 4: write the voltage curve file, then release the snapshot
        if #write_snapshot.volt_buf > 0 then
            write_voltage_data(write_snapshot.model_name, write_snapshot.fly_number,
                write_snapshot.volt_start, write_snapshot.end_time, write_snapshot.volt_buf)
        end
        write_snapshot = nil
        write_state = 0
    end
    if display_mode == 0 then

        lcd.drawText(330, 410, "TX16SMK3  Mini",  SMLSIZE+ square_color)

        local tmcu_value = (field_id[6][2] and value_min_max[6][1]) or 0
        draw_gauge_meter(125, 450, tmcu_value, 100, 100, value_color, square_color)
        lcd.drawText(80, 400, "°C",  square_color)
        local bat_percent = (field_id[5][2] and value_min_max[5][1]) or 0
        local display_num = math.floor(bat_percent)
        draw_digital_display(93, 230, bat_percent, 3, 0, 30, value_color)
        lcd.drawText(188+13, 248, "%",  square_color)
        local battery_capacity = (field_id[4][2] and value_min_max[4][1]) or 0  
         draw_digital_display(93, 170, battery_capacity, 4, 0, 14, value_color)
         lcd.drawText(163, 168, "mah",  square_color)
         draw_ring_progress(150, 205, bat_percent, 100, 120)
        local rpm_value = (field_id[3][2] and value_min_max[3][1]) or 0  
        draw_digital_display(320, 115, rpm_value, 4, 0, 35, value_color)
         lcd.drawText(500, 156, "rpm" , CENTER + VCENTER + square_color)
         local battery_voltage = (field_id[1][2] and value_min_max[1][1]) or 0  
         draw_digital_display(380, 210, battery_voltage, 2, 2, 21, value_color)
         lcd.drawText(320, 210, "Volt", BOLD + square_color)
         lcd.drawText(480, 218, "V",  square_color)
         local vcel_voltage = (field_id[15][2] and value_min_max[15][1]) or 0  
         draw_digital_display(380, 269, vcel_voltage, 2, 2, 21, value_color)
         lcd.drawText(320, 269, "Vcel", BOLD + square_color)
         lcd.drawText(480, 277, "V",  square_color)
          local bec_voltage = (field_id[12][2] and value_min_max[12][1]) or 0  
         draw_digital_display(380, 330, bec_voltage, 2, 2, 21, value_color)
         lcd.drawText(320, 330, "Bec", BOLD + square_color)
         lcd.drawText(480, 338, "V",  square_color)
         local current_value = (field_id[2][2] and value_min_max[2][1]) or 0
             if current_value > current_flight_max_current then
                 current_flight_max_current = current_value
             end
         draw_power_gauge(217, 395, 70, current_value, 300, square_color, value_color)
         draw_ring_progress(217, 395, current_flight_max_current, 300, 80)
         local flight_minutes = math.floor(second[1] % 3600 / 60)
         local flight_seconds = second[1] % 3600 % 60
         draw_time_display(610, 100-30, flight_minutes, flight_seconds, 30, value_color)
         lcd.drawText(553, 120-30, "Time",  square_color)
         local total_all_flights = 0
         local current_model_name = model.getInfo().name
         if telemetry_initialized and current_model_name and current_model_name ~= "" then
             total_all_flights = get_total_flight_count(current_model_name)
         end
         local flight_count = 0
         if telemetry_initialized then
             local current_model_name = model.getInfo().name
             if current_model_name and current_model_name ~= "" then
                 local safe_model_name = string.gsub(current_model_name, "[<>:\"/\\|?*]", "")
                 local target_file_name = "[".. safe_model_name .."]" ..
                     string.format("%d", getDateTime().year) ..
                     string.format("%02d", getDateTime().mon) ..
                     string.format("%02d", getDateTime().day) .. ".log"
                 local target_file_path = LOG_ROOT .. "/" .. target_file_name
                 local file_info = fstat(target_file_path)
                 if file_info ~= nil and file_info.size > 0 then
                     local temp_file_obj = io.open(target_file_path, "r")
                     if temp_file_obj then
                         local temp_log_info = io.read(temp_file_obj, LOG_INFO_LEN + 1)
                         if temp_log_info and string.len(temp_log_info) >= 23 then
                             local str_temp = string.sub(temp_log_info, 21, 23)
                             if tonumber(str_temp) ~= nil then
                                 flight_count = tonumber(str_temp)
                             end
                         end
                         io.close(temp_file_obj)
                     end
                 end
             end
         end
         local total_flight_count = flight_count + session_flight_count
         lcd.drawText(554, 125, "Flight",  square_color)
         draw_digital_display(620, 130, total_all_flights, 4, 0, 13, value_color)
         if total_flight_count > 0 then
            draw_digital_display(710, 130, total_flight_count, 3, 0, 13, value_color)
         else
            draw_digital_display(710, 130, 0, 3, 0, 13, value_color)
         end
    end
    if display_mode == 1 then
        lcd.drawFilledRectangle(0, 0, screen_width, screen_height, bg_color)
        if log_view_mode == 0 then
            draw_model_list(model_list, selected_model_index, square_color, value_color)
        elseif log_view_mode == 1 then
            draw_flight_log_list(viewing_model_name, viewing_log_data, viewing_fly_number,
                                sele_number, square_color, value_color)
        elseif log_view_mode == 2 then
            if viewing_fly_number > 0 and sele_number <= viewing_fly_number and
               viewing_log_data[sele_number] then
                local title = string.format("#%d  %s", sele_number,
                                           string.sub(viewing_log_data[sele_number], 4, 11))
                local log_x = (screen_width - 430) / 2
                draw_log_content(log_x, 50, title, viewing_log_data[sele_number], value_color)
                lcd.drawText(screen_width/2, 20,
                            "Flight Log Details",
                            CENTER + VCENTER + square_color)
                lcd.drawText(screen_width/2, screen_height - 30,
                            "[EXIT] Back",
                            CENTER + VCENTER + SMLSIZE + square_color)
            end
        elseif log_view_mode == 3 then
            -- Curve recording feature is disabled
            
            draw_rpm_chart(viewing_model_name, sele_number, square_color, value_color)
            
        end
 end
    if ENABLE_FLIGHT_REPORT_POPUP and signal_lost then
        popup_button_positions = draw_flight_report_popup(screen_width / 2, screen_height / 2, signal_lost_data, value_color, square_color)
    end
end
return {
    name = NAME,
    options = options,
    create = create,
    update = update,
    refresh = refresh,
    background = background
}
