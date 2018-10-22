-- @description Realtime performance optimization
-- @version 4.3
-- @author Oleynik
-- @website https://rmmedia.ru/threads/129959/



----------------------------------------------------------------------------------------------------
local msg = function(M) reaper.ShowConsoleMsg(tostring(M).."\n") end
----------------------------------------------------------------------------------------------------
-- TEST_Env = true  -- отображает кривую на треках с айтемами (только для настроек и тестов)

defer_rate = 1

peakrate = 10       -- кол-во пиков Wav кривой в секунду, которые берутся в рассчёт
retrig_sec = 1      -- время в течении которого скрипт не реагирует на понижение уровня пика
attThresh_dB = -60  -- уровень Wav кривой выше которого скрипт включает Fx OnOff
relThresh_dB = -55  -- уровень Wav кривой ниже которого скрипт выключает Fx OnOff
on_offcet = 0.3     -- офсет в секундах на включение, на него быстрее будет включаться
-- ЭТОТ офсет стоит увеличить, если используете в проекте плагины с задержкой!!!
off_offcet = 0.1    -- офсет в секундах на выключение, на него позже будет выключаться
volume_off_dB = -55 -- уровень сигнала на треке при котором выключаются Fx OnOff
volume_off  = 10^(volume_off_dB/20)

----------------Функция проверки дупликатов---------------------------------------------------------
function tableHasObject(table, object)
  local duplicate = false
  for p, addedtrack in pairs(table) do -- проверяем не записан ли трек уже в таблицу,
    -- такое может быть, если пользователь сделал петлю сендов из последующих треков
    if addedtrack == object then
      duplicate = true
    end
  end
  return duplicate
end

----------------Функция получения дерева Треков посылов---------------------------------------------
function GetSendLinkedTracks(track, linked_passed, initial_track) -- функция контроля сендов
  local counttracks = reaper.CountTracks(0)
  local linked = {} -- таблица, в которую записываются все треки ресивы слинкованные друг
  -- за другом по дереву с треком сендом (отправной точкой)
  if linked_passed ~= nil then
    linked = linked_passed -- делаем все записи начиная со второго запуска функции самой себя
  end
  if initial_track == nil then -- входной в функцию трек, для которого создаём таблицу
    initial_track = track
  end
  for z=1, counttracks do
    receivetrack =  reaper.BR_GetMediaTrackSendInfo_Track( track, 0, z-1, 1 ) -- получаем трек,
    -- в который отправляем send
    if initial_track ~= receivetrack then -- не пускаем дальше трек для которого таблицу и делаем,
      -- может появится, если пользователь сделал петлю из сендов
      if receivetrack and tableHasObject(linked, receivetrack) == false then
        table.insert(linked, receivetrack)
        local inner = GetSendLinkedTracks(receivetrack, linked, track)
        linked = inner -- делаем первую запись в таблицу
      end
    end
  end
  return linked
end
----------------------------------------------------------------------------------------------------
----------------Функция получения дерева Folder Треков  и OnOff на них------------------------------
function GetParentLinkedTracks(track, linked_unique)
  local foldertrack = reaper.GetParentTrack( track )
  if foldertrack then
    if tableHasObject(linked_unique, foldertrack) == false then
      table.insert(linked_unique, foldertrack)
      linked_unique = GetParentLinkedTracks(foldertrack, linked_unique)
    end
  end
  return linked_unique
end
----------------------------------------------------------------------------------------------------

-----------------Функция получения точек OnOff для MIDI---------------------------------------------
function GetMIDIItemTrigPoints(item, take)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_start + item_len
  local item_loopsrc = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")
  local take_startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local src_lenPPQ = reaper.BR_GetMidiSourceLenPPQ(take)
  local item_startPPQ = reaper.MIDI_GetPPQPosFromProjTime(take, item_start)
  local item_endPPQ = reaper.MIDI_GetPPQPosFromProjTime(take, item_start + item_len)
  ------------------------------------------------
  local buf = {} -- 0-127 = notes, 128 = hold_pedal
  ---------
  function buf_state()
    return next(buf) -- Возвр. true, когда таблица не пуста
  end
  ---------
  function NoteOn(chan, note) -- устанавливает бит, соотв. каналу
    buf[note] = (buf[note] or 0) | (1<<chan)
  end
  ---------
  function NoteOff(chan, note) -- убирает бит, соотв. каналу
    if buf[note] then buf[note] = buf[note] & (~(1<<chan))
      if buf[note] == 0 then buf[note] = nil end
    end
  end
  ------------------------------------------------
  local retval, notecnt, ccevtcnt, textsyxevtcnt = reaper.MIDI_CountEvts(take)
  local evt_cnt = notecnt*2 + ccevtcnt + textsyxevtcnt

  local trig_ppq = {}
  for i = 1, evt_cnt do
    local retval, selected, muted, ppqpos, msg = reaper.MIDI_GetEvt(take, i-1,false,false,0,"")
    local b1, b2, b3 = string.byte(msg, 1, 3)
    local msg_type, msg_chan = (b1 & 0xF0), (b1 & 0x0F)
    --------------------------
    local note_on, note_off -- notes(0-127) or pedal(128) on/off
    if msg_type == 0x90 then
      if b3 > 0 then note_on = true else note_off = true end
    elseif msg_type == 0xB0 and b2 == 64 then
      if b3 > 0 then note_on = true else note_off = true end
      b2 = 128 -- I use 128 for hold pedal
    elseif msg_type == 0x80 then note_off = true
    end
    --------------------------
    if note_on then
      if not buf_state() then trig_ppq[#trig_ppq+1] = {ppqpos, true} end
      NoteOn(msg_chan, b2)
    elseif note_off then
      NoteOff(msg_chan, b2)
      if not buf_state() then trig_ppq[#trig_ppq+1] = {ppqpos, false} end
    end
  end

  ------------------------------------------------
  local loop_cnt = math.ceil((item_endPPQ - item_startPPQ)/src_lenPPQ)
  if take_startoffs > 0 then loop_cnt = loop_cnt + 1 end
  --------------------------
  local point_cnt = #trig_ppq -- src trig points cnt
  local trig_points = {}
  for i = 1, loop_cnt do
    local loop_start = src_lenPPQ * (i-1)
    for j = 1, point_cnt do
      local ppqpos, state = loop_start + trig_ppq[j][1], trig_ppq[j][2]
      local time = reaper.MIDI_GetProjTimeFromPPQPos(take, ppqpos)
      if time >= item_start and time <= item_end then
        trig_points[#trig_points+1] = {time, state}
      end
    end
  end

  ------------------------------------------------
  if #trig_points > 0 then
    if trig_points[1][2] ~= false then  -- Start всегда false, начало айтема
      table.insert(trig_points, 1, {item_start, false})
    else
      table.insert(trig_points, 1, {item_start, true})
      table.insert(trig_points, 1, {item_start, false})
    end
    if trig_points[#trig_points][2] ~= false then  -- End всегда false, конец айтема
      table.insert(trig_points, {item_start + item_len, false})
    end
  end
  ------------------
  return trig_points
end
----------------------------------------------------------------------------------------------------

-----------------Функция получения точек OnOff для Audio--------------------------------------------
function GetAudioItemTrigPoints(item)
  local take = reaper.GetActiveTake(item)
  take = reaper.GetActiveTake(item)
  if not take then return {}   -- пока пустая таблица
  elseif reaper.TakeIsMIDI(take) then return GetMIDIItemTrigPoints(item, take)
  end
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  ------------------
  local starttime, n_chans, n_spls, want_extra_type, buf, retval
  n_chans = 1         -- GetPeaks only 1 channel now!!!
  n_spls = math.ceil(item_len*peakrate) -- Note: its Peak Samples!
  want_extra_type = 0 -- get min, max, no spectral
  buf = reaper.new_array(n_spls * n_chans * 2) -- max, min, only for 1 channel
  buf.clear()         -- Clear buffer
  retval = reaper.GetMediaItemTake_Peaks(take, peakrate, item_start, n_chans, n_spls, want_extra_type, buf)
  ------------------
  local attThresh  = 10^(attThresh_dB/20)
  local relThresh  = 10^(relThresh_dB/20)
  local trig_points = {}
  local last_trig = false
  for i = 1, n_spls do
    local max_peak = math.max(math.abs(buf[i]), math.abs(buf[i+n_spls]))
    if not last_trig and max_peak >= attThresh then
      trig_points[#trig_points+1] = {item_start + (i-1)/peakrate, true}; last_trig = true
    elseif last_trig and max_peak < relThresh then
      trig_points[#trig_points+1] = {item_start + (i-1)/peakrate, false}; last_trig = false
    end
  end
  ------------------
  if #trig_points > 0 then
    if trig_points[1][2] ~= false then  -- Start всегда false, начало айтема
      table.insert(trig_points, 1, {item_start, false})
    end
    if trig_points[#trig_points][2] ~= false then  -- End всегда false, конец айтема
      table.insert(trig_points, {item_start + item_len, false})
    end
  end
  ------------------
  return trig_points
end
----------------------------------------------------------------------------------------------------

-----------------Функция создания точек OnOff для Audio и MIDI--------------------------------------
function CreateTrackTrigPoints(track)
  ------------------
  local items_trig = {} -- Таблица триг. точек для айтемов
  local item_cnt = reaper.CountTrackMediaItems(track)
  for i = 1, item_cnt do
    local item = reaper.GetTrackMediaItem(track, i-1)
    items_trig[i] = GetAudioItemTrigPoints(item)
  end
  ------------------
  local mix_trig = {} -- Таблица триг. точек без учета перекрытия и т.п.
  for i = 1, item_cnt do
    local t = items_trig[i]
    for j = 1, #t do
      local time, trig = t[j][1], t[j][2]
      if mix_trig[time] then time = time+0.00001 end
      mix_trig[time] = {i, trig}
    end
  end
  -----
  local i2time = {} -- Таблица конвертирования индекс-время
  for k in pairs(mix_trig) do i2time[#i2time+1] = k end
  table.sort(i2time)
  ------------------
  local trig_tb = {} -- Таблица для расчета перекрытий
  function trigger(item, trig)
    trig_tb[item] = trig
    for i = 1, item_cnt do
      if trig_tb[i] then return true end
    end
    return false
  end
  ------------------
  local track_trig = {} -- Таблица триг. точек для трека
  local last_trig, last_time = false, -math.huge
  local retrig = retrig_sec -- Retrig time in sec
  for i = 1, #i2time do
    local time = i2time[i]
    local item, trig = mix_trig[time][1], mix_trig[time][2]
    local trig = trigger(item, trig)
    if trig ~= last_trig then
      if time - last_time < retrig and trig then table.remove(track_trig)
      else track_trig[#track_trig+1] = {time, trig}
      end
      last_trig, last_time = trig, time
    end
  end
  ------------------
  return track_trig
end
----------------------------------------------------------------------------------------------------

------------Функция даёт знать произошли ли какие то изменения в Проекте в целом--------------------
local Project = {}
function Project.isChanged()
  local change_cnt = reaper.GetProjectStateChangeCount(0)
  if change_cnt ~= Project.change_cnt then
    Project.change_cnt = change_cnt
    return true
  end
end
-----------Функция даёт знать произошли ли какие то изменения в Аудио или Миди айтемах--------------
function GetTrackAudioMIDIHash(track)
  local AH, MH -- audio, midi hash
  local MH = select(2, reaper.MIDI_GetTrackHash(track, true, ""))
  local AA = reaper.CreateTrackAudioAccessor(track)
  if AA then AH = reaper.GetAudioAccessorHash(AA, "")
    reaper.DestroyAudioAccessor(AA)
  end
  return (AH or "") .. (MH or "")
end
----------------------------------------------------------------------------------------------------
function Project.TrackIsChanged(track)
  if not Project.track_hashes then
    Project.track_hashes = {}
  end
  local guid = reaper.GetTrackGUID(track)
  local track_hash = GetTrackAudioMIDIHash(track)
  if Project.track_hashes[guid] ~= track_hash then
    Project.track_hashes[guid] = track_hash
    return true
  end
end
----------------------------------------------------------------------------------------------------

----------------------------------Для настройки скрипта---------------------------------------------
function ActivateEnvelope(track)
  local EnvName = "Volume (Pre-FX)"
  local Env = reaper.GetTrackEnvelopeByName(track, EnvName)
  if not Env then
    reaper.SetOnlyTrackSelected(track)
    reaper.TrackList_AdjustWindows(true)
    reaper.Main_OnCommand(40050, 0) -- Pre-FX Vol Env --
    Env = reaper.GetTrackEnvelopeByName(track, EnvName)
  end
  --- Del old points --
  local sel_start, sel_end = 0, 99999 -- 0-999 range
  reaper.DeleteEnvelopePointRange(Env, sel_start, sel_end)
  reaper.UpdateArrange()
  return Env
end
----------------------------------Для настройки скрипта---------------------------------------------
function CreateEnvelope(track, track_trig)
  local Env = ActivateEnvelope(track)
  ------------------------------------
  local mode = reaper.GetEnvelopeScalingMode(Env)
  local Gain = reaper.ScaleToEnvelopeMode(mode,  0.3) -- 0.3 - gain for testing
  local Gain1 = reaper.ScaleToEnvelopeMode(mode, 1)   -- 1 - gain
  ------------------------------------
  local shape, tens , sel = 2,0,0
  local pre, post = on_offcet+0.001, off_offcet+0.001 -- pre-open, post-close
  reaper.InsertEnvelopePoint(Env, 0, Gain, shape, tens, sel, true) -- 0-point
  for i=1, #track_trig, 1 do
    if not track_trig[i][2] then
      reaper.InsertEnvelopePoint(Env, track_trig[i][1]+off_offcet,     Gain1, shape, tens, sel, true)
      reaper.InsertEnvelopePoint(Env, track_trig[i][1]+post, Gain,  shape, tens, sel, true)
    elseif track_trig[i][2] then
      reaper.InsertEnvelopePoint(Env, track_trig[i][1]-pre, Gain,  shape, tens, sel, true)
      reaper.InsertEnvelopePoint(Env, track_trig[i][1]-on_offcet,      Gain1, shape, tens, sel, true)
    end
  end
  ------------------------------------
  reaper.Envelope_SortPoints(Env)
  reaper.UpdateArrange()
end
----------------------------------------------------------------------------------------------------

------------Получаем положение (время) курсора: сто при плее, что при стопе-------------------------
function getCursorPositionAndPlayState()
  local cursorposition
  local isPlay = false
  if reaper.GetPlayState(0) == 1 or reaper.GetPlayState(0) == 5 then
    cursorposition =  reaper.GetPlayPosition()
    isPlay = true
  else
    cursorposition =  reaper.GetCursorPosition()
  end
  return cursorposition, isPlay
end

------------Выясняем нужно включить или выключить FX OnOff в точке где сейчас курсор----------------
function checkTrackTrigetByCursor(cursorposition, track_trig)
  local t_end = 0
  local t_onoff = 0
  for i=1, #track_trig, 1 do
    if track_trig[i][2] then
      point_time = track_trig[i][1] - on_offcet
    else
      point_time = track_trig[i][1] + off_offcet
    end
    if cursorposition < point_time and t_end == 0 then
      if track_trig[i][2] then
        t_onoff = 0
      else
        t_onoff = 1
      end
      t_end = 1
    elseif cursorposition > track_trig[#track_trig][1] + off_offcet then
      t_onoff = 0
      t_end = 1
    end
  end
  return t_onoff
end

-----------Получаем все прилинкованные к данному треку парент треки т треки посылов-----------------
function getAllLinksForTrack(track)
  local allLinkedTracks = {}
  allLinkedTracks = GetSendLinkedTracks(track, allLinkedTracks)
  allLinkedTracks = GetParentLinkedTracks(track, allLinkedTracks)
  return allLinkedTracks
end

-------Основная Функция управляющая FX On Off на всех зависящих друг от друга треках----------------
function setOnOffTracksLinks(tracks)
  local unique_links = {}
  for guid, trackonoff in pairs(tracks) do
    local ltrack = reaper.BR_GetMediaTrackByGUID(0, guid)
    local links = getAllLinksForTrack(ltrack)
    table.insert(links, ltrack)
    for i=1, #links do
      local key = links[i]
      if unique_links[key] ~= 1 then -- хотябы один трек отправляет на трек сенд - он будет вкл.
        unique_links[key] = trackonoff
      end
    end
  end

  for unique_track, unique_onoff in pairs(unique_links) do
    local fx_onoff = reaper.GetMediaTrackInfo_Value(unique_track, "I_FXEN")
    if fx_onoff ~= unique_onoff then
      reaper.SetMediaTrackInfo_Value(unique_track, "I_FXEN", unique_onoff)
    end
  end
end
----------------------------------------------------------------------------------------------------
----------Получаем максимальную громкость в точке плей курсора по всем слинкованным  трекам---------
function getTracksVolumePeak(tracks)
  v_peak = 0
  for id, utrack in pairs(tracks) do -- для треков посылов и фолдеров вместе
    local v_peak_s_0 = reaper.Track_GetPeakInfo( utrack, 0 )
    local v_peak_s_1 = reaper.Track_GetPeakInfo( utrack, 1 )
    v_peak_n = (v_peak_s_0 + v_peak_s_1)/2
    if v_peak_n > v_peak then
      v_peak = v_peak_n
    end
  end
  return v_peak
end

----------------------------------------------------------------------------------------------------

----------------Main--------------------------------------------------------------------------------

local start_noitem = 1
local tracks_tracktrig = {}
local final_tracks = {}
function main ()
  if TEST_Env then
    gfx.setfont(1,"Verdana",25)
    gfx.set(1, 0, 0)
    gfx.x, gfx.y = 0, 0
    gfx.drawstr("TEST!", 5, gfx.w, gfx.h*0.6)

    if proc_time_ms then
      gfx.x, gfx.y = 0, gfx.h*0.4
      gfx.drawstr(string.format("%0.1f %s",proc_time_ms, "ms"), 5, gfx.w, gfx.h)
    end
  end
  -----------------------
  local cursorposition, isPlay = getCursorPositionAndPlayState()
  -- if Project.isChanged() then
    local start_time = reaper.time_precise() -- start time test
    local track_cnt = reaper.CountTracks(0)
    for i = 1, track_cnt do
      local track = reaper.GetTrack(0, i-1)
      local GUID = reaper.GetTrackGUID(track)
      local recarm_state = reaper.GetMediaTrackInfo_Value( track, "I_RECARM" )
      if recarm_state == 1 then
        final_tracks[GUID] = 1
      else
        final_tracks[GUID] = 0
        local item_cnt = reaper.CountTrackMediaItems(track)
        if item_cnt ~= 0 then
          if Project.TrackIsChanged(track) then
            local track_w_item_trig = CreateTrackTrigPoints(track)
            tracks_tracktrig[GUID] = track_w_item_trig
            if TEST_Env then
              CreateEnvelope(track, track_w_item_trig) -- test env
            end
          end
        else
          if start_noitem == 1 then
            reaper.SetMediaTrackInfo_Value(track, "I_FXEN", 0)
            start_noitem = 0
          end
        end
      end
    end
    proc_time_ms  = (reaper.time_precise() - start_time)*1000 -- time test
  -- end

  for guid, track_trig in pairs(tracks_tracktrig) do
    local track = reaper.BR_GetMediaTrackByGUID(0, guid)
    local trig = checkTrackTrigetByCursor(cursorposition, tracks_tracktrig[guid])
    if trig == 1 then
      final_tracks[guid] = 1
    else
      local track = reaper.BR_GetMediaTrackByGUID(0, guid)
      local links = getAllLinksForTrack(track)
      table.insert(links, track)
      local peak = getTracksVolumePeak(links)
      if peak < volume_off then
        local recarm_state = reaper.GetMediaTrackInfo_Value( track, "I_RECARM" )
        if recarm_state ~= 1 then
          final_tracks[guid] = 0
        end
      end
    end
  end
  setOnOffTracksLinks(final_tracks)
end

---------------- Mainloop---------------------------------------------------------------------------
cycle = 0
function mainloop ()
  cycle = cycle+1
  if cycle == defer_rate then
    main()
    cycle = 0
  end

  if TEST_Env then
    char = gfx.getchar()
    if char~=-1 then reaper.defer(mainloop) end --defer
    gfx.update() -- Update gfx window
  else
    reaper.defer(mainloop)
  end
end

if TEST_Env then
  gfx.init("Test", 100,100)
end
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
function DeleteEnvelope()
  local track_cnt = reaper.CountTracks(0)
  for i = 1, track_cnt do
    local track = reaper.GetTrack(0, i-1)
    local EnvName = "Volume (Pre-FX)"
    local Env = reaper.GetTrackEnvelopeByName(track, EnvName)
    if Env then
      local sel_start, sel_end = 0, 999 -- 0-999 range
      reaper.DeleteEnvelopePointRange(Env, sel_start, sel_end)
      reaper.SetOnlyTrackSelected(track)
      reaper.TrackList_AdjustWindows(true)
      reaper.Main_OnCommand(40050, 0) -- Pre-FX Vol Env --
    end
  end
  reaper.Main_OnCommand(40769, 0) -- unselect All
  reaper.UpdateArrange()
end

scan_data = {} -- запись таблицы для восстановления состояния FX on/off в ДО старта скрипта
function ScanTrackStart () -- нужно подумать и объеденить с ScanTrack с индексом 0
  counttracks = reaper.CountTracks(0)
  if counttracks == nil then return end
  for i = 1, counttracks do
    local track = reaper.GetTrack(0,i-1)
    if track ~= nil then
      local GUID = reaper.GetTrackGUID( track )
      local fx_onoff = reaper.GetMediaTrackInfo_Value( track, "I_FXEN" )
      scan_data[GUID] = fx_onoff -- для каждого GUID трека пишется состояния FX on/off
    end
  end
end

function ReplaceTracksEnd () -- функция восстановления состояния FX on/off и цвет трека из таблицы
  -- созданной при старте скрипта
  for guid, fxs in pairs(scan_data) do
    local track = reaper.BR_GetMediaTrackByGUID(0, guid)
    if track then
      reaper.SetMediaTrackInfo_Value(track, "I_FXEN", fxs)
    end
  end
end

----------------------------------------------------------------------------------------------------
-- Set ToolBar Button ON
function SetButtonON()
  ScanTrackStart() -- старт функции сканирующей при старте состояние FX on/off и цвет трека
  is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  state = reaper.GetToggleCommandStateEx( sec, cmd )
  reaper.SetToggleCommandState( sec, cmd, 1 ) -- Set ON
  reaper.RefreshToolbar2( sec, cmd )
end
--
-- Set ToolBar Button OFF
function SetButtonOFF()
  if TEST_Env then
    DeleteEnvelope()
  end
  ReplaceTracksEnd () -- запуск функции восстановления состояния FX on/off
  is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  state = reaper.GetToggleCommandStateEx( sec, cmd )
  reaper.SetToggleCommandState( sec, cmd, 0 ) -- Set OFF
  reaper.RefreshToolbar2( sec, cmd )
end
----------------------------------------------------------------------------------------------------


SetButtonON() -- функция запуска срипта с "поджигом" кнопки тулбара

mainloop () -- основная функция дефера

reaper.atexit(SetButtonOFF) -- выход из скрипта с запуском функции выхода с тушением кнопки тулбара
