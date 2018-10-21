-- @description Split selected items under mouse cursor (select right)
-- @version 1.0
-- @author Archie
-- @website https://rmmedia.ru/threads/118091/page-76#post-2287461
-- @about Разделить выбранный элемент под курсором мыши и все выбранные элементы в этой позиции (выбрать слева)
-- @changelog
--    init

 --[[
    * Category:    Item
    * Description: Split selected item under mouse cursor and
                      all selected items in this position(select right)
    * Oписание:    Разделить выбранный элемент под курсором мыши и все 
                           выбранные элементы в этой позиции (выбрать с права)
    * GIF          ---
    * Author:      Archie
    * Version:     1.3
    * customer     HDVulcan(RMM Forum)
    * gave idea    Supa75  (RMM Forum)
 --=================================]]
   
 
 
 
     local MIDI_item = 1 --Если курсор под миди элементом, то если 
                  -- MIDI_item =  0  |- будет резать четко под мышкой
                  -- MIDI_item =  1  |- будет резать по ближайшему активному делению сетки
                                    --------------------------
                  -- If the cursor is under the midi item, then if
                  -- MIDI_item = 0 | - will be cut clearly under the arm
                  -- MIDI_item = 1 | - will cut by the closest active grid division                
                  -----------------------------------------------------------------                  
     
     
     
     local SnapGrid = 1
                 -- SnapGrid =  -1   |- будет резать по ближайшему пересечению нуля в элементах
                                                  -- отталкивается от последнего элемента.Работает 
                                                  -- только, если  Selected = 1 и выделен элемент
                 -- SnapGrid =   0   |- будет резать четко под мышкой
                 -- SnapGrid =   1   |- будет резать по ближайшему активному делению сетки
                              ------------------------------------------------------------
                 -- SnapGrid = -1   | - will cut at the nearest zero crossing in the elements
                                                   -- pushes away from the last element. Works
                                                   -- only if Selected = 1 and an item is selected
                 -- SnapGrid =  0   | - will be cut clearly under the arm
                 -- SnapGrid =  1   | - will cut by the nearest active grid division
                 -------------------------------------------------------------------             
    
    
    
     local Selected = 1
                 -- Selected = 0 скрипт сработает на любом элементе
                 -- Selected = 1 скрипт сработает только на выделенном элементе
                                                  -----------------------------
                 -- Selected = 0 script will work on any element  
                 -- Selected = 1 the script will only work on the selected item
                                                             
     
     
     
     
     --======================================================================================
     --////////////////////////////////////   SCRIPT   \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
     --======================================================================================

     
 
 
     -----------------------------------------------------------------------------
     local function No_Undo()end; local function no_undo()reaper.defer(No_Undo)end
     -----------------------------------------------------------------------------
     
     
     
     if not SnapGrid  then SnapGrid  = 1 end
     if not Selected  then Selected  = 1 end  
     if not MIDI_item then MIDI_item = 1 end  
     ---
     
     
     local function Split_item_sel_right (item,Pos) 
         local TrackNumber_  
         local pos = reaper.GetMediaItemInfo_Value( item, "D_POSITION" )
         local len = reaper.GetMediaItemInfo_Value( item, "D_LENGTH" ) 
         if pos < Pos and len + pos >= Pos then                    
             reaper.SplitMediaItem( item, Pos )
             local tr = reaper.GetMediaItemTrack( item )
             TrackNumber_ =  reaper.GetMediaTrackInfo_Value( tr, "IP_TRACKNUMBER" )
             local CountTrItems = reaper.CountTrackMediaItems( tr )
             for i = 1,CountTrItems do
                 local item = reaper.GetTrackMediaItem( tr, i-1 )
                 local pos = reaper.GetMediaItemInfo_Value( item, "D_POSITION" )
                 local len = reaper.GetMediaItemInfo_Value( item, "D_LENGTH" ) 
                 if pos == Pos then
                     reaper.SetMediaItemInfo_Value( item, "B_UISEL",1 )
                 else
                     reaper.SetMediaItemInfo_Value( item, "B_UISEL",0 )
                 end
                 ---  
             end  
         end
         return TrackNumber_
     end
     --=====================
 
     
      
      
     local window, segment, details = reaper.BR_GetMouseCursorContext()
     local item = reaper.BR_GetMouseCursorContext_Item()
     if item then
         if Selected > 0 then
             sel = reaper.GetMediaItemInfo_Value( item, "B_UISEL")
         end
     end    
     if not item or sel == 0 then no_undo()return end
     --==============================================
     
     
     
     
     local take = reaper.GetActiveTake( item )
     local TakeIsMIDI = reaper.TakeIsMIDI(take)
     if TakeIsMIDI == true then
         if MIDI_item <= 0 then
             SnapGrid = 0 
         else    
             SnapGrid = 1  
         end
     end
     --=======================
     
     
     
     local Pos = reaper.BR_PositionAtMouseCursor(true)
     if Selected > 0 then
         for i = reaper.CountSelectedMediaItems(0)-1,0,-1 do
             item = reaper.GetSelectedMediaItem( 0, i )
             local it_pos = reaper.GetMediaItemInfo_Value( item, "D_POSITION" )
             local it_end =(reaper.GetMediaItemInfo_Value(item,"D_LENGTH")+it_pos)
             if it_pos > Pos then
                 reaper.SetMediaItemInfo_Value( item,"B_UISEL",0 )
             end
             if it_end < Pos then
                 reaper.SetMediaItemInfo_Value( item,"B_UISEL",0 )     
             end
         end
     end
     
 
 
     local name_script = "Split selected item under mouse cursor and"
                 .."all selected items in this position(select right)"
     reaper.Undo_BeginBlock() 
     
     
     --local Pos = reaper.BR_PositionAtMouseCursor(true)
     if SnapGrid > 0 then 
         --Pos = reaper.BR_GetClosestGridDivision(Pos)
         Pos = reaper.SnapToGrid(0,Pos)
     elseif SnapGrid == -1  then
         reaper.PreventUIRefresh(1) 
         local CurPos = reaper.GetCursorPosition()
         reaper.SetEditCurPos(Pos,0,0)
         reaper.Main_OnCommand(41995, 0)
         --Move edit cursor to nearest zero crossing in items
         Pos = reaper.GetCursorPosition()
         reaper.SetEditCurPos(CurPos,0,0)
         reaper.PreventUIRefresh(-1) 
     end
     
     
     local TrackNumber = Split_item_sel_right(item,Pos) 
     
     local countTrack = reaper.CountTracks( 0 )
     for i = 1,countTrack do
         local track = reaper.GetTrack( 0, i-1 )
         local TrNumb =  reaper.GetMediaTrackInfo_Value( track, "IP_TRACKNUMBER" )
         if TrNumb ~= TrackNumber then
             local CountTrItems = reaper.CountTrackMediaItems( track )
             for i2 = 1,CountTrItems do
                 local item = reaper.GetTrackMediaItem( track, i2-1 )
                 local pos = reaper.GetMediaItemInfo_Value( item, "D_POSITION" )
                 local len = reaper.GetMediaItemInfo_Value( item, "D_LENGTH" )  
                 if pos <= Pos and len + pos >= Pos then 
                     if reaper.GetMediaItemInfo_Value( item, "B_UISEL")== 1 then    
                         Split_item_sel_right (item,Pos) 
                         break
                     end
                 else
                     reaper.SetMediaItemInfo_Value( item, "B_UISEL",0)  
                 end
             end
         end    
     end
     reaper.Undo_EndBlock(name_script,0)
     reaper.UpdateArrange()
 
  
         
