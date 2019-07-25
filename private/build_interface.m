function h = build_interface(self)

  % check if window is already opened
  
  % else create
  h = openfig('../stargo.fig')
  
  % mouseUpCallback to detect release of mouse over NSEW buttons
  set(h, 'Tag','StarGo_window','WindowButtonUpFcn', @(src,evnt)WindowButtonUpFcn(src, evnt,self))
  
  % assign button callbacks to private functions
  StarGo_RA   goto(self, ra, '')
  StarGo_DEC
  StarGo_zoom
  StarGo_N
  StarGo_S
  StarGo_W
  StarGo_E
  StarGo_Stop
  
  % assign menu items callbacks
  File_Save
  File_SaveAs
  File_Print
  File_Close
  StarGo_goto
  StarGo_STOP
  StarGo_sync
  StarGo_zoom_in
  StarGo_zoom_out
  StarGo_zoom_guide
  StarGo_zoom_find
  StarGo_zoom_slew
  Home_set
  Home_goto
  Track_sidereal
  Track_sun
  Track_moon
  Track_none
  StarGo_reset
  View_Update
  View_Auto_Update
  View_SkyMap
  View_Location
  View_Help
  View_About
