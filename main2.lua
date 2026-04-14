
-------  大贝壳 出品 V1.0

local NAME = "DBK_Tx15Pro"
local VERSION = "v1.0"
local TopValue = 10
local crsf_field = { "Vbat", "Curr", "Hspd", "Capa", "Bat%", "Tesc", "Tmcu", "1RSS", "2RSS", "RQly", "Thr", "Vbec", "ARM", "Gov", "Vcel","Tmcu","PID#" }
local TELE_ITEMS = #crsf_field

local LOG_INFO_LEN = 22
local LOG_DATA_LEN = 115

local value_min_max = {}
local field_id = {}
local bank_info = { current = 1, name = "Bank 1" }
local tg_pic_obj
local default_pic_obj

-- 缓存变量
local cached_model_name = ""
local cached_pic_path = ""
local last_audio_time = 0
local led_cache = { last_start_color = 0, last_end_color = 0 }
local log_write_timer = 0

local hold_locked = false
local button_pressed = false
local signal_lost = false
local last_rqly_status = false
local telemetry_initialized = false
local current_peak_value = 0  -- 记录电流峰值
local signal_lost_data = {
    model_name = "",
    flight_time = "00:00",
    max_power = 0,
    max_current = 0
}

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
local arm_flag = false
local second_save = 0
local display_log_flag = false
local display_mode = 0

local options = {
    { "SquareColor", COLOR, WHITE },
    { "BackgroundColor", COLOR, BLACK },
    { "ValueColor", COLOR, GREEN },
    { "DispLED", BOOL, 0 },
    { "HoldSwitch", SWITCH, 0 }
}

local radioH = 0
local radio_name, version = getVersion()

if version and string.find(version, "tx15") then
    radioH = 30
elseif version and string.find(version, "tx16s") then
    radioH = 0
else
    radioH = 0
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

    -- 初始化缓存的模型名称
    cached_model_name = ""

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
    signal_lost = false
    last_rqly_status = false
    telemetry_initialized = false

    -- 先使用默认文件名，在refresh中动态更新
    file_name = "[DBK_Tx15Pro]" ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. ".log"
    file_path = "/WIDGETS/DBK_Tx15Pro/logs/" .. file_name

    local file_info = fstat(file_path)
    local read_count = 1
    if file_info ~= nil then
        if file_info.size > 0 then
            file_obj = io.open(file_path, "r")
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
        end
    else
        -- 不创建默认文件，设置默认的log_info
        log_info =
            string.format("%d", getDateTime().year) .. '/' ..
            string.format("%02d", getDateTime().mon) .. '/' ..
            string.format("%02d", getDateTime().day) .. '|' ..
            "00:00:00" .. '|' ..
            "00\n"
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

    -- 只在create时加载默认图片
    default_pic_obj = Bitmap.open("/WIDGETS/DBK_Tx15Pro/default.png")

    return widget
end

local function update(widget, options)
    widget.options = options
end

local function background(widget)
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

-- 绘制半圆形功率仪表盘
local function draw_power_gauge(center_x, center_y, radius, power_value, max_power, gauge_color, needle_color)
    -- 限制最大功率显示范围（单位：瓦）
    local display_max = max_power or 5000  -- 默认最大5000W (5kW)
    power_value = math.max(0, math.min(display_max, power_value))

    -- 270度弧：从225度顺时针旋转15度后的位置，到135度
    local start_angle = 225  -- 起始角度（向右旋转15度）
    local end_angle = 135    -- 结束角度（向右旋转15度）
    local total_sweep = 270  -- 总扫描角度

    -- 绘制270度弧边框（分两段）
    -- 第一段：从225度到360度
    lcd.drawArc(center_x, center_y, radius, start_angle, 360, gauge_color)
    lcd.drawArc(center_x, center_y, radius - 2, start_angle, 360, gauge_color)
    -- 第二段：从0度到135度
    lcd.drawArc(center_x, center_y, radius, 0, end_angle, gauge_color)
    lcd.drawArc(center_x, center_y, radius - 2, 0, end_angle, gauge_color)

    -- 绘制刻度线和刻度值（11个刻度，每个27度）
    local num_ticks = 11  -- 0%, 10%, 20% ... 100%
    for i = 0, num_ticks - 1 do
        -- 从225度开始，顺时针方向每次减27度（0度在起点，顺时针增加）
        local angle_deg = start_angle - (i * 27)
        local angle_rad = math.rad(angle_deg)

        -- 计算刻度线的起点和终点
        local tick_start_r = radius - 5
        local tick_end_r = radius - 12
        local x1 = center_x + tick_start_r * math.cos(angle_rad)
        local y1 = center_y - tick_start_r * math.sin(angle_rad)
        local x2 = center_x + tick_end_r * math.cos(angle_rad)
        local y2 = center_y - tick_end_r * math.sin(angle_rad)

        lcd.drawLine(x1, y1, x2, y2, SOLID, gauge_color)

        -- 绘制刻度值（每隔2个刻度显示一次）
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

    -- 计算指针角度（0-100%映射到225度顺时针减少到-45度）
    local percentage = power_value / display_max
    local needle_angle_deg = start_angle - (percentage * total_sweep)
    local needle_angle_rad = math.rad(needle_angle_deg)

    -- 绘制指针
    local needle_length = radius - 15
    local needle_x = center_x + needle_length * math.cos(needle_angle_rad)
    local needle_y = center_y - needle_length * math.sin(needle_angle_rad)

    -- 绘制指针（带一点厚度）
    lcd.drawLine(center_x, center_y, needle_x, needle_y, SOLID, needle_color)
    lcd.drawLine(center_x + 1, center_y, needle_x + 1, needle_y, SOLID, needle_color)
    lcd.drawLine(center_x, center_y + 1, needle_x, needle_y + 1, SOLID, needle_color)

    -- 绘制中心圆点
    lcd.drawFilledRectangle(center_x - 2, center_y - 2, 5, 5, needle_color)

    -- 绘制当前功率值文本
    local power_str = ""
    --if power_value >= 1000 then
        power_str = string.format("%.0f°C", power_value)
    --else
      --  power_str = string.format("%.0fW", power_value)
    --end
    lcd.drawText(center_x, center_y + 35, power_str,  needle_color + CENTER + VCENTER)
end

-- 半圆形仪表盘（固定0-300量程，270度弧）
local function draw_semicircle_gauge(center_x, center_y, radius, current_value, gauge_color, needle_color, inner_value)
    -- 固定显示范围 0-300
    local display_max = 300
    current_value = math.max(0, math.min(display_max, current_value))
    inner_value = inner_value or 0
    inner_value = math.max(0, math.min(display_max, inner_value))

    -- 270度弧：从225度顺时针旋转15度后的位置，到135度
    local start_angle = 225  -- 起始角度（向右旋转15度）
    local end_angle = 135    -- 结束角度（向右旋转15度）
    local total_sweep = 270  -- 总扫描角度

    -- 绘制270度弧边框（分两段）
    -- 第一段：从225度到360度
    lcd.drawArc(center_x, center_y, radius, start_angle, 360, gauge_color)
    lcd.drawArc(center_x, center_y, radius - 2, start_angle, 360, gauge_color)
    -- 第二段：从0度到135度
    lcd.drawArc(center_x, center_y, radius, 0, end_angle, gauge_color)
    lcd.drawArc(center_x, center_y, radius - 2, 0, end_angle, gauge_color)

    -- 绘制圆环内部的渐变色填充（如果 inner_value > 0）
    if inner_value > 0 then
        local inner_percentage = inner_value / display_max
        local inner_sweep_angle = inner_percentage * total_sweep

        -- 填充圆环区域（radius-2 到 radius 之间）
        for r = radius - 2, radius do
            -- 将填充区域分成更多段来实现平滑颜色渐变
            local segment_count = 100  -- 100段实现非常平滑的渐变
            for seg = 0, segment_count - 1 do
                local seg_percentage = seg / segment_count
                -- 从 start_angle (225度) 开始，逆时针增加角度（向上、向右填充）
                local seg_angle_start = start_angle + (seg_percentage * inner_sweep_angle)
                local seg_angle_end = start_angle + ((seg + 1) / segment_count * inner_sweep_angle)

                -- 根据在0-300范围内的实际位置计算颜色，实现RGB渐变
                local color_pos = seg_percentage * inner_percentage
                local color

                -- 使用RGB渐变：绿(0,255,0) -> 黄(255,255,0) -> 橙(255,128,0) -> 红(255,0,0)
                local r_val, g_val, b_val
                if color_pos < 0.33 then
                    -- 0-33%: 绿色到黄色渐变
                    local t = color_pos / 0.33
                    r_val = math.floor(t * 255)
                    g_val = 255
                    b_val = 0
                    color = lcd.RGB(r_val, g_val, b_val)
                elseif color_pos < 0.67 then
                    -- 33-67%: 黄色到橙色渐变
                    local t = (color_pos - 0.33) / 0.34
                    r_val = 255
                    g_val = math.floor(255 - t * 127)
                    b_val = 0
                    color = lcd.RGB(r_val, g_val, b_val)
                else
                    -- 67-100%: 橙色到红色渐变
                    local t = (color_pos - 0.67) / 0.33
                    r_val = 255
                    g_val = math.floor(128 - t * 128)
                    b_val = 0
                    color = lcd.RGB(r_val, g_val, b_val)
                end

                -- 处理角度超过360度的情况
                if seg_angle_start >= 360 then
                    lcd.drawArc(center_x, center_y, r, seg_angle_start - 360, seg_angle_end - 360, color)
                elseif seg_angle_end > 360 then
                    lcd.drawArc(center_x, center_y, r, seg_angle_start, 360, color)
                    lcd.drawArc(center_x, center_y, r, 0, seg_angle_end - 360, color)
                else
                    lcd.drawArc(center_x, center_y, r, seg_angle_start, seg_angle_end, color)
                end
            end
        end
    end

    -- 绘制刻度线和刻度值（11个刻度，每个27度）
    local num_ticks = 11  -- 0%, 10%, 20% ... 100%
    for i = 0, num_ticks - 1 do
        -- 从225度开始，顺时针方向每次减27度（0度在起点，顺时针增加）
        local angle_deg = start_angle - (i * 27)
        local angle_rad = math.rad(angle_deg)

        -- 计算刻度线的起点和终点
        local tick_start_r = radius - 5
        local tick_end_r = radius - 12
        local x1 = center_x + tick_start_r * math.cos(angle_rad)
        local y1 = center_y - tick_start_r * math.sin(angle_rad)
        local x2 = center_x + tick_end_r * math.cos(angle_rad)
        local y2 = center_y - tick_end_r * math.sin(angle_rad)

        lcd.drawLine(x1, y1, x2, y2, SOLID, gauge_color)

        -- 绘制刻度值（每隔2个刻度显示一次，0, 60, 120, 180, 240, 300）
        if i % 2 == 0 then
            local value = (display_max / 10) * i
            local label = string.format("%.0f", value)

            local text_r = radius - 22
            local text_x = center_x + text_r * math.cos(angle_rad)
            local text_y = center_y - text_r * math.sin(angle_rad)
            lcd.drawText(text_x, text_y, label, SMLSIZE+CENTER + VCENTER + gauge_color)
        end
    end

    -- 计算指针角度（0-100%映射到225度顺时针减少到-45度）
    local percentage = current_value / display_max
    local needle_angle_deg = start_angle - (percentage * total_sweep)
    local needle_angle_rad = math.rad(needle_angle_deg)

    -- 绘制指针
    local needle_length = radius - 15
    local needle_x = center_x + needle_length * math.cos(needle_angle_rad)
    local needle_y = center_y - needle_length * math.sin(needle_angle_rad)

    -- 绘制指针（带一点厚度）
    lcd.drawLine(center_x, center_y, needle_x, needle_y, SOLID, needle_color)
    lcd.drawLine(center_x + 1, center_y, needle_x + 1, needle_y, SOLID, needle_color)
    lcd.drawLine(center_x, center_y + 1, needle_x, needle_y + 1, SOLID, needle_color)

    -- 绘制中心圆点
    lcd.drawFilledRectangle(center_x - 2, center_y - 2, 5, 5, needle_color)

    -- 绘制当前值文本
    local value_str = string.format("%.0fA", current_value)
    lcd.drawText(center_x , center_y + 34, value_str,  needle_color + CENTER + VCENTER)
end


local function fuel_percentage(xs, ys, capa, number, text_color)
    -- 渐变圆环：将圆环分成多段，每段使用不同颜色
    local segments = 36  -- 圆环分成36段，每段10度
    local segment_angle = 10  -- 每段的角度

    for i = 0, segments - 1 do
        local percent = (i / segments) * 100  -- 当前段对应的百分比
        -- 计算渐变颜色：红色(0%) -> 黄色(50%) -> 绿色(100%)
        local red, green, blue
        if percent < 50 then
            -- 0-50%: 红色到黄色
            red = 255
            green = math.floor(percent * 5.1)  -- 0 -> 255
            blue = 0
        else
            -- 50-100%: 黄色到绿色
            red = math.floor(255 - (percent - 50) * 5.1)  -- 255 -> 0
            green = 255
            blue = 0
        end
        local segment_color = lcd.RGB(red, green, blue)

        -- 计算当前段的起始和结束角度（从底部180度开始，顺时针绘制）
        local start_angle = 180 + i * segment_angle
        local end_angle = start_angle + segment_angle

        -- 只绘制已充满的部分
        if percent <= number then
            lcd.drawAnnulus(xs, ys, 45, 70, start_angle, end_angle, segment_color)
        end
    end

    lcd.drawText(xs + 2, ys - 10, string.format("%d%%", number), CENTER + VCENTER + DBLSIZE + text_color)
    lcd.drawText(xs, ys + 14, string.format("%dmAh", capa), CENTER + VCENTER + text_color)
end

local function throttle_percentage_bar(xs, ys, thr_value, border_color, text_color)
    local bar_width = 105
    local bar_height = 20
    thr_value = math.max(0, math.min(100, thr_value))

    -- 绘制白色矩形边框
    lcd.drawRectangle(xs, ys, bar_width, bar_height, WHITE)

    if thr_value > 0 then
        -- 将进度条分成10段，每段10%
        local segments = 10
        local segment_width = bar_width / segments

        for i = 0, segments - 1 do
            local percent = (i * 10) + 5  -- 每段的中间百分比值（5%, 15%, 25%...）
            local segment_start_percent = i * 10  -- 这段的起始百分比

            -- 只绘制已填充的部分
            if segment_start_percent < thr_value then
                -- 计算渐变颜色：绿色(0%) -> 黄色(50%) -> 红色(100%)
                local red, green, blue
                if percent < 50 then
                    -- 0-50%: 绿色到黄色
                    red = math.floor(percent * 5.1)  -- 0 -> 255
                    green = 255
                    blue = 0
                else
                    -- 50-100%: 黄色到红色
                    red = 255
                    green = math.floor(255 - (percent - 50) * 5.1)  -- 255 -> 0
                    blue = 0
                end
                local segment_color = lcd.RGB(red, green, blue)

                -- 计算当前段的位置和宽度
                local seg_x = xs + 1 + math.floor(i * segment_width)
                local seg_width = math.floor(segment_width)

                -- 处理最后可能不完整的段
                if segment_start_percent + 10 > thr_value then
                    local remaining_percent = thr_value - segment_start_percent
                    seg_width = math.floor(segment_width * (remaining_percent / 10))
                end

                if seg_width > 0 then
                    lcd.drawFilledRectangle(seg_x, ys + 1, seg_width, bar_height - 2, segment_color)
                end
            end
        end
    end

    -- 绘制10个分段的分隔线（9条）
    for i = 1, 9 do
        local line_x = xs + math.floor((bar_width / 10) * i)
        lcd.drawLine(line_x, ys + 2, line_x, ys + bar_height - 2, SOLID, BLACK)
    end

   -- lcd.drawText(xs + bar_width / 2, ys + bar_height / 2, string.format("%d%%", thr_value), CENTER + VCENTER + SMLSIZE + WHITE)
end


local function rqly_signal_bars(xs, ys, rqly_percent, default_color)
    local block_size = 5
    local block_spacing = 7
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
    draw_rounded_rectangle(xs, ys, 400 - 1, 175 - 1, 2, flags)
    lcd.drawLine(xs, ys + 28, xs + 400 - 2, ys + 28, SOLID, flags)
    lcd.drawLine(xs + 200, ys + 28, xs + 200, ys + 175 - 2, SOLID, flags)
    lcd.drawText(xs + 5, ys + 5, title, flags)
    lcd.drawText(xs + 5, ys + 30,
        "Time: " .. extract[2] .. '\n' ..
        "Capa: " .. extract[3] .. "[mAh]\n" ..
        "Fuel: " .. extract[4] .. "[%]\n" ..
        "HSpd: " .. extract[5] .. "[rpm]\n" ..
        "Throttle: " .. extract[20] .. "[%]\n" ..
        "Current: " .. extract[6] .. "[A]\n" ..
        "Power: " .. extract[7] .. "[W]"
        , flags)
    lcd.drawText(xs + 205, ys + 30,
        "Battery: " .. extract[8] .. " -> " .. extract[9] .. "[V]\n" ..
        "BEC: " .. extract[22] .. " -> " .. extract[21] .. "[V]\n" ..
        "ESC: " .. extract[11] .. " -> " .. extract[10] .. "[°C]\n" ..
        "MCU: " .. extract[13] .. " -> " .. extract[12] .. "[°C]\n" ..
        crsf_field[8] .. ": " .. extract[14] .. " -> " .. extract[15] .. "[dB]\n" ..
        crsf_field[9] .. ": " .. extract[16] .. " -> " .. extract[17] .. "[dB]\n" ..
        crsf_field[10] .. ": " .. extract[18] .. " -> " .. extract[19] .. "[%]"
        , flags)
end

-- 音频播放辅助函数
local function safe_play_tone(freq, length, pause, flags, freqIncr)
    local current_time = getTime()
    if current_time - last_audio_time > 10 then -- 防止音频重叠，至少间隔100ms
        last_audio_time = current_time
        playTone(freq, length, pause, flags or PLAY_NOW, freqIncr)
    end
end

local function get_all_log_files()
    local log_files = {}
    local log_dir = "/WIDGETS/DBK_Tx15Pro/logs"

    -- 只获取当天日期
    local today_date = string.format("%d%02d%02d", getDateTime().year, getDateTime().mon, getDateTime().day)

    -- 尝试使用 EdgeTX 的文件列表 API
    local files = nil

    -- 尝试不同的 API 函数
    if system and system.getFileList then
        -- EdgeTX 2.9+
        files = system.getFileList(log_dir)
    elseif getFileList then
        -- 旧版本
        files = getFileList(log_dir)
    end

    if files then
        -- 成功获取文件列表，遍历处理
        for i = 1, #files do
            local file = files[i]
            if file and type(file) == "string" then
                -- 解析文件名格式: [ModelName]YYYYMMDD.log
                local model_name, date_str = string.match(file, "%[(.+)%](%d%d%d%d%d%d%d%d)%.log")

                if model_name and date_str == today_date then
                    -- 这是当天的日志文件，读取飞行次数
                    local file_path = log_dir .. "/" .. file
                    local temp_file = io.open(file_path, "r")
                    if temp_file then
                        local log_header = io.read(temp_file, LOG_INFO_LEN + 1)
                        io.close(temp_file)

                        if log_header and string.len(log_header) >= 23 then
                            local flight_count = tonumber(string.sub(log_header, 21, 23)) or 0
                            if flight_count > 0 then
                                table.insert(log_files, {
                                    model_name = model_name,
                                    flight_count = flight_count,
                                    date = today_date
                                })
                            end
                        end
                    end
                end
            end
        end
    else
        -- API 不可用，返回空列表并显示提示
        -- 可以在界面上显示一个提示信息
    end

    return log_files
end

local function draw_flight_report_popup(xs, ys, data, value_color, square_color)
    local popup_width = 450
    local popup_height = 200
    local popup_x = xs - popup_width / 2
    local popup_y = ys - popup_height / 2

    -- 绘制半透明背景
    lcd.drawFilledRectangle(popup_x, popup_y, popup_width, popup_height, BLACK)

    -- 绘制边框 (使用 value_color)
    draw_rounded_rectangle(popup_x, popup_y, popup_width, popup_height, 10, value_color)
    lcd.drawFilledRectangle(popup_x + 3, popup_y + 3, popup_width - 6, 2, value_color)
    lcd.drawFilledRectangle(popup_x + 3, popup_y + popup_height - 5, popup_width - 6, 2, value_color)

    -- 标题 (使用 value_color)
    lcd.drawText(popup_x + popup_width / 2, popup_y + 20, "Flight Report", CENTER + VCENTER + DBLSIZE + value_color)

    -- 第一列：标签
    local col1_x = popup_x + 20
    lcd.drawText(col1_x, popup_y + 60, "Model:", square_color)
    lcd.drawText(col1_x, popup_y + 90, "Flight Time:", square_color)
    lcd.drawText(col1_x, popup_y + 120, "Max Power:", square_color)
    lcd.drawText(col1_x, popup_y + 150, "Max Current:", square_color)

    -- 第二列：数值
    local col2_x = popup_x + 160
    lcd.drawText(col2_x, popup_y + 60, data.model_name, BOLD + square_color)
    lcd.drawText(col2_x, popup_y + 90, data.flight_time, BOLD + square_color)
    local power_str = string.format("%dW", data.max_power)
    if data.max_power >= 1000 then
        power_str = string.format("%.1fkW", data.max_power / 1000)
    end
    lcd.drawText(col2_x, popup_y + 120, power_str, BOLD + square_color)
    lcd.drawText(col2_x, popup_y + 150, string.format("%.1fA", data.max_current), BOLD + square_color)

    -- 第三列：按钮
    local col3_x = popup_x + 300
    local button_width = 130
    local button_height = 30
    local button_spacing = 10

    -- 按钮1: Close
    local btn1_y = popup_y + 55
    draw_rounded_rectangle(col3_x, btn1_y, button_width, button_height, 5, value_color)
    lcd.drawText(col3_x + button_width / 2, btn1_y + button_height / 2, "Close", CENTER + VCENTER + square_color)

    -- 按钮2: View Current Log
    local btn2_y = btn1_y + button_height + button_spacing
    draw_rounded_rectangle(col3_x, btn2_y, button_width, button_height, 5, value_color)
    lcd.drawText(col3_x + button_width / 2, btn2_y + button_height / 2, "Current Log", CENTER + VCENTER + SMLSIZE + square_color)

    -- 按钮3: View All Logs (已注释)
    -- local btn3_y = btn2_y + button_height + button_spacing
    -- draw_rounded_rectangle(col3_x, btn3_y, button_width, button_height, 5, value_color)
    -- lcd.drawText(col3_x + button_width / 2, btn3_y + button_height / 2, "All Logs", CENTER + VCENTER + square_color)
end

-- 绘制直角轮廓（右侧）
local function draw_right_angle(x, y, color, h_length, v_length)
    -- 绘制横线（从起点向右）
    lcd.drawLine(x, y, x + h_length, y, SOLID, color)
    -- 绘制竖线（从起点向下）
    lcd.drawLine(x, y, x, y + v_length, SOLID, color)
end

-- 绘制直角轮廓（左侧，相对右侧旋转180度）
local function draw_left_angle(x, y, color, h_length, v_length)
    -- 绘制横线（从起点向左）
    lcd.drawLine(x, y, x - h_length, y, SOLID, color)
    -- 绘制竖线（从起点向上）
    lcd.drawLine(x, y, x, y - v_length, SOLID, color)
end

local function refresh(widget, event, touchState)
    local screen_width =  LCD_W or widget.zone.w
    local screen_height =  LCD_H or widget.zone.h

    -- 如果弹窗没有显示，处理正常事件
    if not signal_lost then
        if event == nil then
        elseif event ~= 0 then
        if touchState then
            if event == EVT_TOUCH_FIRST then
                safe_play_tone(100, 50, 50)
            elseif event == EVT_TOUCH_TAP then
                safe_play_tone(200, 50, 50)
            end
        end
        if event == EVT_VIRTUAL_NEXT_PAGE then
            display_mode = (display_mode + 1) % 3
            display_log_flag = (display_mode == 1)
            safe_play_tone(200, 100, 100)
        elseif event == EVT_VIRTUAL_PREV_PAGE then
            if display_mode == 0 then
                display_mode = 2
            elseif display_mode == 1 then
                display_mode = 0
            elseif display_mode == 2 then
                display_mode = 1
                display_log_flag = false
            end
            safe_play_tone(200, 100, 100)
        elseif event == EVT_VIRTUAL_NEXT then
            if display_mode == 1 and not display_log_flag then
                if fly_number > 0 then
                    if sele_number < fly_number then
                        sele_number = sele_number + 1
                    else
                        sele_number = 1
                    end
                    safe_play_tone(200, 50, 100)
                end
            end
        elseif event == EVT_VIRTUAL_PREV then
            if display_mode == 1 and not display_log_flag then
                if fly_number > 0 then
                    if sele_number > 1 then
                        sele_number = sele_number - 1
                    else
                        sele_number = fly_number
                    end
                    safe_play_tone(200, 50, 100)
                end
            end
        elseif event == EVT_VIRTUAL_ENTER then
            if display_mode == 1 then
                if fly_number > 0 and sele_number > 0 and sele_number <= fly_number and log_data[sele_number] then
                    display_log_flag = not display_log_flag
                    safe_play_tone(100, 200, 100, PLAY_NOW, 10)
                else
                    safe_play_tone(3000, 100, 50)
                end
            else
                safe_play_tone(600, 50, 50)
            end
        elseif event == EVT_VIRTUAL_EXIT then
            display_mode = 0
            display_log_flag = false
            safe_play_tone(10000, 200, 100, PLAY_NOW, -60)
        end
        end
    else
        -- 弹窗显示中，处理弹窗事件
        if event ~= nil and event ~= 0 then
            -- 按键关闭（ENTER 或 EXIT）
            if event == EVT_VIRTUAL_ENTER or event == EVT_VIRTUAL_EXIT then
                signal_lost = false
                safe_play_tone(200, 100, 100)
            -- 触摸关闭（点击按钮）
            elseif event == EVT_TOUCH_TAP and touchState then
                -- 计算弹窗和按钮位置
                local popup_width = 450
                local popup_height = 200
                local popup_x = (screen_width - popup_width) / 2
                local popup_y = (screen_height - popup_height) / 2
                local col3_x = popup_x + 300
                local button_width = 130
                local button_height = 30
                local button_spacing = 10
                local btn1_y = popup_y + 55
                local btn2_y = btn1_y + button_height + button_spacing

                -- 检测是否点击了 Close 按钮区域
                if touchState.x >= col3_x and touchState.x <= col3_x + button_width and
                   touchState.y >= btn1_y and touchState.y <= btn1_y + button_height then
                    signal_lost = false
                    safe_play_tone(200, 100, 100)
                -- 检测是否点击了 Current Log 按钮区域
                elseif touchState.x >= col3_x and touchState.x <= col3_x + button_width and
                       touchState.y >= btn2_y and touchState.y <= btn2_y + button_height then
                    -- 关闭弹窗，进入日志查看模式
                    signal_lost = false
                    display_mode = 1
                    display_log_flag = true
                    -- 选择最新的日志记录
                    if fly_number > 0 then
                        sele_number = fly_number
                    end
                    safe_play_tone(200, 100, 100)
                -- 检测是否点击了 All Logs 按钮区域 (已注释)
                -- elseif touchState.x >= col3_x and touchState.x <= col3_x + button_width and
                --        touchState.y >= btn2_y + button_height + button_spacing and touchState.y <= btn2_y + button_height * 2 + button_spacing then
                --     -- 关闭弹窗，进入所有日志列表模式
                --     signal_lost = false
                --     display_mode = 2
                --     safe_play_tone(200, 100, 100)
                end
            end
        end
    end

    lcd.setColor(CUSTOM_COLOR, widget.options.BackgroundColor)
    local bg_color = lcd.getColor(CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, widget.options.SquareColor)
    local square_color = lcd.getColor(CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, widget.options.ValueColor)
    local value_color = lcd.getColor(CUSTOM_COLOR)

    -- 如果是日志显示模式，直接绘制全屏日志界面
    if display_mode == 1 and display_log_flag then
        -- 清空整个屏幕背景
        lcd.drawFilledRectangle(0, 0, screen_width, screen_height, bg_color)

        -- 显示日志内容
        if fly_number > 0 and sele_number > 0 and sele_number <= fly_number and log_data[sele_number] then
            local title = "Flight #" .. string.format("%02d", sele_number) .. "/" .. string.format("%02d", fly_number)
            draw_log_content(40, 50, title, log_data[sele_number], square_color)
        end

        -- 显示提示信息
        lcd.drawText(10, 10, "Press EXIT to return", square_color)

        return  -- 直接返回，不绘制主界面
    end

    -- 如果是所有日志列表模式 (已注释)
    -- if display_mode == 2 then
    --     -- 清空整个屏幕背景
    --     lcd.drawFilledRectangle(0, 0, screen_width, screen_height, bg_color)

    --     -- 标题
    --     lcd.drawText(screen_width / 2, 20, "Today's Flight Logs", CENTER + DBLSIZE + value_color)
    --     lcd.drawText(10, 10, "Press EXIT to return", square_color)

    --     -- 获取所有日志文件
    --     local all_logs = get_all_log_files()

    --     -- 显示日志列表
    --     local y_pos = 60
    --     local line_height = 35

    --     if #all_logs == 0 then
    --         lcd.drawText(screen_width / 2, screen_height / 2 - 20, "No flights today", CENTER + VCENTER + square_color)
    --         lcd.drawText(screen_width / 2, screen_height / 2 + 10, "or API not available", CENTER + VCENTER + SMLSIZE + square_color)
    --     else
    --         -- 表头
    --         lcd.drawText(50, y_pos, "Model Name", BOLD + square_color)
    --         lcd.drawText(350, y_pos, "Flights", BOLD + square_color)

    --         -- 绘制分隔线
    --         y_pos = y_pos + 25
    --         lcd.drawLine(40, y_pos, screen_width - 40, y_pos, SOLID, value_color)
    --         y_pos = y_pos + 15

    --         -- 显示每个日志条目
    --         for i, log_entry in ipairs(all_logs) do
    --             if y_pos < screen_height - 40 then
    --                 lcd.drawText(50, y_pos, log_entry.model_name, MIDSIZE + square_color)
    --                 lcd.drawText(350, y_pos, string.format("%d", log_entry.flight_count), MIDSIZE + value_color)
    --                 y_pos = y_pos + line_height
    --             end
    --         end

    --         -- 显示总计
    --         local total_flights = 0
    --         for _, log_entry in ipairs(all_logs) do
    --             total_flights = total_flights + log_entry.flight_count
    --         end
    --         lcd.drawLine(40, screen_height - 60, screen_width - 40, screen_height - 60, SOLID, value_color)
    --         lcd.drawText(50, screen_height - 50, "Total", BOLD + square_color)
    --         lcd.drawText(350, screen_height - 50, string.format("%d", total_flights), BOLD + value_color)
    --     end

    --     return  -- 直接返回，不绘制主界面
    -- end

    -- LED控制逻辑：处理开启和关闭
    if LED_STRIP_LENGTH and LED_STRIP_LENGTH > 0 then
        if widget.options.DispLED == 1 then
            -- LED开关开启
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
            -- LED开关关闭，关闭所有LED
            if led_cache.last_start_color ~= 0 or led_cache.last_end_color ~= 0 then
                led_cache.last_start_color = 0
                led_cache.last_end_color = 0

                for i = 0, LED_STRIP_LENGTH - 1 do
                    setRGBLedColor(i, 0, 0, 0)  -- 设置为黑色（关闭）
                end
                applyRGBLedColors()
            end
        end
    end
    lcd.drawFilledRectangle(0, 0, screen_width, screen_height, bg_color)
    local title_height = 25
    -- 时间
    local current_time = getDateTime()
    local time_str = string.format("%02d:%02d:%02d", current_time.hour, current_time.min, current_time.sec)
    lcd.drawText(385, 260+radioH, time_str, BOLD + square_color)

    -- 检查模型名称是否改变，只在改变时重新加载图片和更新文件名
    local current_model_name = model.getInfo().name
    if cached_model_name ~= current_model_name then
        cached_model_name = current_model_name
        cached_pic_path = "/WIDGETS/DBK_Tx15Pro/"..string.sub(cached_model_name, 2)..".png"

        -- 更新文件名为模型名称（只在模型名称变化时执行一次）
        if current_model_name and current_model_name ~= "" then
            -- 清理文件名中的无效字符
            local safe_model_name = string.gsub(current_model_name, "[<>:\"/\\|?*]", "")
            local new_file_name = "[".. safe_model_name .. "]" ..
                string.format("%d", getDateTime().year) ..
                string.format("%02d", getDateTime().mon) ..
                string.format("%02d", getDateTime().day) .. ".log"
            local new_file_path = "/WIDGETS/DBK_Tx15Pro/logs/" .. new_file_name 

            -- 只有文件名真的改变了才更新
            if new_file_path ~= file_path then
                file_name = new_file_name
                file_path = new_file_path
            end
        end

        if fstat(cached_pic_path) then
            tg_pic_obj = Bitmap.open(cached_pic_path)
        else
            tg_pic_obj = nil
        end
    end

     -- 模型名称
    lcd.drawText(255, 260+radioH, cached_model_name, BOLD + value_color)

    local tx_voltage = getValue("tx-voltage") or getValue("TxBt") or 0
    local tx_battery_str = string.format("%.1fV", tx_voltage)

    local tx_color = value_color   
    if tx_voltage < 6.5 then
        tx_color = RED
    elseif tx_voltage >= 6.5 and tx_voltage <= 7.0 then
        tx_color = YELLOW
    end

    lcd.drawText(400, 13, "Tx", BOLD + square_color)
    lcd.drawText(420, 13, tx_battery_str, BOLD + tx_color)
    lcd.drawText(30, title_height / 2+TopValue, "Bank" , CENTER + VCENTER + square_color)
    lcd.drawText(100, title_height / 2+TopValue, "HOLD" , CENTER + VCENTER + square_color)
    lcd.drawText(170, title_height / 2+TopValue, "RSSI" , CENTER + VCENTER + square_color)
    -- 直接读取PID#的值（crsf_field数组第17个元素）
    bank_info.current = (field_id[17][2] and value_min_max[17][1]) or 1

    local bank_color = square_color
    if bank_info.current == 1 then
        bank_color = lcd.RGB(0, 100, 255)      
    elseif bank_info.current == 2 then
        bank_color = lcd.RGB(255, 165, 0)      
    elseif bank_info.current == 3 then
        bank_color = lcd.RGB(255, 255, 0)      
    end
    lcd.drawText(20, 35+TopValue, tostring(bank_info.current), CENTER + VCENTER + BOLD + MIDSIZE + bank_color)

    local arm_status = (field_id[13][2] and value_min_max[13][1]) or 0  
    local gov_status = (field_id[14][2] and value_min_max[14][1]) or 0  
    
    
    

    local is_armed = false
    if field_id[13][2] then
        
        is_armed = (arm_status == 1 or arm_status == 3)
    else
        
        is_armed = arm_switch_active
    end

    local gov_state_names = { "OFF", "IDLE", "SPOOLUP", "RECOVERY", "ACTIVE", "THR-OFF", "LOST-HS", "AUTOROT", "BAILOUT" }
    if is_armed then
        lcd.drawText(280, 13+TopValue, "GOV:", CENTER + VCENTER + square_color) 
        if field_id[14][2] then
            local gov_name = gov_state_names[gov_status + 1] or "UNK"
            if gov_name == "SPOOLUP" then
                lcd.drawText(340, 12+TopValue, gov_name, CENTER + VCENTER +  value_color)
            else 
                lcd.drawText(320, 12+TopValue, gov_name, CENTER + VCENTER +  value_color)
            end
        else
            lcd.drawText(340, 12+TopValue, "ARMED", CENTER + VCENTER +  GREEN)
        end
    else
        lcd.drawText(280, 13+TopValue, "ARM:", CENTER + VCENTER + square_color)
        if field_id[13][2] then
            lcd.drawText(345, 15+TopValue, "DISARMED", CENTER + VCENTER +   RED)
        elseif widget.options.ArmSwitch ~= 0 then
            lcd.drawText(345, 15+TopValue, "DISARMED", CENTER + VCENTER +   RED)
        else
            lcd.drawText(345, 15+TopValue, "NO TELE", CENTER + VCENTER +   BLINK + RED)
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

    local hold_status = hold_active and "On" or "Off"
    local hold_color = hold_active and GREEN or RED
    lcd.drawText(97, 35+TopValue, hold_status, CENTER + VCENTER + MIDSIZE + hold_color)

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
        end
    end

    minutes[1] = string.format("%02d", math.floor(second[1] % 3600 / 60))
    seconds[1] = string.format("%02d", second[1] % 3600 % 60)
    hours = string.format("%02d", math.floor(total_second / 3600))
    minutes[2] = string.format("%02d", math.floor(total_second % 3600 / 60))
    seconds[2] = string.format("%02d", total_second % 3600 % 60)

    -- 优化日志写入：每5秒写入一次，避免频繁I/O
    log_write_timer = log_write_timer + 1
    if write_en_flag and fly_number < 57 and second[1] > 30 and log_write_timer >= 250 then -- 约5秒(假设50fps)
        log_write_timer = 0

        -- 强制使用模型名称，如果获取不到就不写入
        local current_model_name = model.getInfo().name
        if not current_model_name or current_model_name == "" then
            -- 如果没有模型名称，跳过写入
            write_en_flag = false
            return
        end

        -- 使用模型名称创建文件名
        local safe_model_name = string.gsub(current_model_name, "[<>:\"/\\|?*]", "")
        write_en_flag = true
        -- 如果模型名称包含 BK_Dashboard，不写文件
        if string.find(safe_model_name, "DBK_Dashboard") then
            write_en_flag = false
        end

        if write_en_flag then
            file_name = "[".. safe_model_name .."]" ..
                string.format("%d", getDateTime().year) ..
                string.format("%02d", getDateTime().mon) ..
                string.format("%02d", getDateTime().day) .. ".log"
            file_path = "/WIDGETS/DBK_Dashboard/logs/" .. file_name

            -- 检查文件是否存在
            local existing_file_info = fstat(file_path)
            if existing_file_info and existing_file_info.size > 0 then
                -- 文件存在，需要读取所有数据，更新记录数，然后重写整个文件
                local temp_file_obj = io.open(file_path, "r")
                local existing_log_data = {}
                local existing_log_info = ""
                local existing_fly_count = 0

                if temp_file_obj then
                    existing_log_info = io.read(temp_file_obj, LOG_INFO_LEN + 1)
                    if existing_log_info and string.len(existing_log_info) >= 23 then
                        local str_temp = string.sub(existing_log_info, 21, 23)
                        if tonumber(str_temp) ~= nil then
                            existing_fly_count = tonumber(str_temp)
                        end
                    end

                    -- 读取所有现有记录
                    local read_count = 1
                    while true do
                        local data = io.read(temp_file_obj, LOG_DATA_LEN + 1)
                        if #data == 0 then
                            break
                        else
                            existing_log_data[read_count] = data
                            read_count = read_count + 1
                        end
                    end
                    io.close(temp_file_obj)
                end

                -- 更新飞行记录数
                fly_number = existing_fly_count + 1

                -- 重写整个文件
                file_obj = io.open(file_path, "w")
                if not file_obj then
                    write_en_flag = false
                    return
                end

                -- 写入更新后的头部信息
                log_info =
                    string.format("%d", getDateTime().year) .. '/' ..
                    string.format("%02d", getDateTime().mon) .. '/' ..
                    string.format("%02d", getDateTime().day) .. '|' ..
                    hours .. ':' .. minutes[2] .. ':' .. seconds[2] .. '|' ..
                    string.format("%02d", fly_number) .. "\n"
                io.write(file_obj, log_info)

                -- 写入所有现有记录
                for i = 1, existing_fly_count do
                    if existing_log_data[i] then
                        io.write(file_obj, existing_log_data[i])
                    end
                end

                -- 写入新记录
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

                io.write(file_obj, log_data[fly_number])
            else
                -- 文件不存在，创建新文件，设置为第一次飞行
                fly_number = 1

                file_obj = io.open(file_path, "w")
                if not file_obj then
                    write_en_flag = false
                    return
                end

                log_info =
                    string.format("%d", getDateTime().year) .. '/' ..
                    string.format("%02d", getDateTime().mon) .. '/' ..
                    string.format("%02d", getDateTime().day) .. '|' ..
                    hours .. ':' .. minutes[2] .. ':' .. seconds[2] .. '|' ..
                    string.format("%02d", fly_number) .. "\n"
                io.write(file_obj, log_info)

                for w = 1, fly_number - 1 do
                    io.write(file_obj, log_data[w])
                end

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

                io.write(file_obj, log_data[fly_number])
            end
            io.close(file_obj)
            write_en_flag = false
        end
    end

    local battery_voltage = (field_id[1][2] and value_min_max[1][1]) or 0  
    lcd.drawText(179, 63+TopValue, "Volt" , CENTER + VCENTER + square_color)
    local battery_voltage_str = string.format("%.2fv", battery_voltage)
     if battery_voltage == 0 then
        lcd.drawText( 195, 82+TopValue, battery_voltage_str, CENTER + VCENTER +MIDSIZE+ value_color)  
     else
        lcd.drawText( 200, 82+TopValue, battery_voltage_str, CENTER + VCENTER +MIDSIZE+ value_color)  
     end

    lcd.drawText(180, 110+TopValue, "Vcel" , CENTER + VCENTER + square_color)
    local vcel_voltage = (field_id[15][2] and value_min_max[15][1]) or 0  
    local vcel_voltage_str = "0.00v"
    if vcel_voltage > 0 then
        vcel_voltage_str = string.format("%.2fv", vcel_voltage)
    end
    lcd.drawText(195, 129+TopValue, vcel_voltage_str, CENTER + VCENTER + MIDSIZE + value_color)
    lcd.drawText(179, 155+TopValue, "Bec" , CENTER + VCENTER + square_color)    
    local bec_voltage = (field_id[12][2] and value_min_max[12][1]) or 0  
    local bec_voltage_str = "0.00v"
    if bec_voltage > 0 then
        bec_voltage_str = string.format(bec_voltage < 10 and "%.2fv" or "%.1fv", bec_voltage)
    end
    lcd.drawText(195, 175+TopValue, bec_voltage_str, CENTER + VCENTER +MIDSIZE + value_color)
    
    -- 飞行时间
    local battery_percent = (field_id[5][2] and value_min_max[5][1]) or 0  
    local battery_capacity = (field_id[4][2] and value_min_max[4][1]) or 0  
    fuel_percentage(80, 140, battery_capacity,battery_percent, value_color)
    lcd.drawText(280, 158, "Time" , CENTER + VCENTER + square_color)
    local flight_time_str = string.format("%s:%s", minutes[1], seconds[1])
    lcd.drawText(340, 158, flight_time_str, CENTER + VCENTER +MIDSIZE+ value_color)
    
    -- 统计当天这个模型的飞行记录数量
    local flight_count = 0
    local current_model_name = model.getInfo().name
    if current_model_name and current_model_name ~= "" then
        local safe_model_name = string.gsub(current_model_name, "[<>:\"/\\|?*]", "")
        local target_file_name = "[".. safe_model_name .."]" ..
            string.format("%d", getDateTime().year) ..
            string.format("%02d", getDateTime().mon) ..
            string.format("%02d", getDateTime().day) .. ".log"
        local target_file_path = "/WIDGETS/DBK_Dashboard/logs/" .. target_file_name

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

    -- 飞行次数
    lcd.drawText(400, 158, flight_count, CENTER + VCENTER +MIDSIZE+ value_color)
    
    
    local throttle_percent = (field_id[11][2] and value_min_max[11][1]) or 0  
    throttle_percentage_bar(310, 118, throttle_percent, value_color, value_color)
    lcd.drawText(273, 128, "Thr" , CENTER + VCENTER + square_color)
    lcd.drawText(438, 118+TopValue, string.format("%d%%", throttle_percent) , CENTER + VCENTER + square_color)
 
    local rpm_value = (field_id[3][2] and value_min_max[3][1]) or 0  
    local rpm_str = "0"
    if rpm_value > 0 then
        rpm_str = string.format("%d", rpm_value)
    end
    lcd.drawText(335, 65+TopValue, rpm_str, CENTER + VCENTER + DBLSIZE + BOLD + value_color)
    lcd.drawText(430, 78+TopValue, "Rpm" , CENTER + VCENTER + square_color)
    lcd.drawFilledRectangle(260, 105, 190, 1, square_color)
     
    local rqly_percent = (field_id[10][2] and value_min_max[10][1]) or 0
    rqly_signal_bars(200, 10+TopValue, rqly_percent, WHITE)

    if rqly_percent > 0 then
        lcd.drawText(175, 33+TopValue, string.format("%ddB", rqly_percent), CENTER + VCENTER  + value_color)
    else
        lcd.drawText(165, 33+TopValue, "---", CENTER + VCENTER + MIDSIZE + RED)
    end

    -- 信号丢失检测逻辑（陀螺仪断电检测）
    -- 检测 RQly 和其他遥测字段是否都丢失
    local has_telemetry = false
    if field_id[10][2] then
        -- RQly 字段存在
        if rqly_percent > 0 then
            has_telemetry = true
        end
    end

    -- 首次检测到遥测信号，标记为已初始化
    if has_telemetry == true and telemetry_initialized == false then
        telemetry_initialized = true
        last_rqly_status = true
    end

    -- 只有在遥测已初始化后，才检测信号丢失
    if telemetry_initialized == true then
        if has_telemetry == false and last_rqly_status == true then
            -- 信号刚刚丢失，保存当前数据
            signal_lost = true
            last_rqly_status = false
            signal_lost_data.model_name = cached_model_name
            signal_lost_data.flight_time = string.format("%s:%s", minutes[1], seconds[1])
            signal_lost_data.max_power = power_max[1]
            signal_lost_data.max_current = value_min_max[2][2]
            safe_play_tone(2000, 300, 100, PLAY_NOW)
        elseif has_telemetry == true then
            -- 信号恢复
            last_rqly_status = true
            signal_lost = false
        end
    end
    --  模型名称
    if tg_pic_obj then
        if version and string.find(version, "tx15") then
             lcd.drawBitmap(tg_pic_obj, 254, 150+radioH)
        else
             lcd.drawBitmap(tg_pic_obj, 254, 150+radioH)
        end
    else
        if default_pic_obj then
            lcd.drawBitmap(default_pic_obj, 254, 150+radioH)
        end
    end
     
    if version and string.find(version, "tx15") then

       local current_value = (field_id[2][2] and value_min_max[2][1]) or 0

       -- 更新电流峰值逻辑
       if not is_armed then
           -- 解除武装时清零峰值
           current_peak_value = 0
       else
           -- 武装时，只在当前值超过峰值时更新
           if current_value > current_peak_value then
               current_peak_value = current_value
           end
       end

       local current_str = "0.0A"
       if current_value > 0 then
           current_str = string.format("%.1fA", current_value)
       end
       --lcd.drawText(12, 240+TopValue, "Current", BOLD +  square_color)
      -- lcd.drawText(75, 240+TopValue, current_str, BOLD +  value_color)

       local power_value = battery_voltage * current_value
       local power_str = "0.0W"
       if power_value > 0 then
           if power_value >= 1000 then
               power_str = string.format("%.1fkW", power_value / 1000)
           else
               power_str = string.format("%.0fW", power_value)
           end
       end
     --  lcd.drawText(125, 240+TopValue, "Power", BOLD +  square_color)
       --lcd.drawText(180, 240+TopValue, power_str, BOLD +  value_color)

       local tmcu_value = (field_id[7][2] and value_min_max[7][1]) or 0
       -- 绘制温度仪表盘（半圆形带刻度和指针，0-100度）
       draw_power_gauge(190, 260+TopValue, 50, tmcu_value, 100, square_color, value_color)

       -- 绘制仪表盘（固定0-300量程）使用峰值作为内部填充
       draw_semicircle_gauge(65, 260+TopValue, 50, current_value, square_color, value_color, current_peak_value)
    end

    -- 绘制信号丢失弹窗（在最上层）
    if signal_lost then
        draw_flight_report_popup(screen_width / 2, screen_height / 2, signal_lost_data, value_color, square_color)
    end

    -- 测试绘制直角
   -- draw_right_angle(252, 150+radioH-2, value_color, 20, 20)
   -- draw_left_angle(250+205, 150+radioH+100+2, value_color, 20, 20)


end

return {
    name = NAME,
    options = options,
    create = create,
    update = update,
    refresh = refresh,
    background = background
}