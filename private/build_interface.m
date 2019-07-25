function h = build_interface(self)

  % check if window is already opened
  
  % else create
  h = openfig('../stargo.fig')
  
  % mouseUpCallback to detect release of mouse over NSEW buttons
  set(h, 'Tag','StarGo_window','WindowButtonUpFcn', @(src,evnt)WindowButtonUpFcn(src, evnt,self))
  
  % assign button callbacks to private functions
  callbacks = {...
    'StarGo_RA',     @(src,evnt)goto(self, get(gcbo, 'String'), ''); ...
    'StarGo_DEC',    @(src,evnt)goto(self, '', get(gcbo, 'String')); ...
    'StarGo_zoom',   @(src,evnt)zoom(self, get(gcbo, 'Value')); ...
    'StarGo_N',      @(src,evnt)move(self, 'n'); ...
    'StarGo_S',      @(src,evnt)move(self, 's'); ...
    'StarGo_W',      @(src,evnt)move(self, 'w'); ...
    'StarGo_E',      @(src,evnt)move(self, 'e'); ...
    'StarGo_Stop',   @(src,evnt)stop(self); ...
    'StarGo_goto',       @(src,evnt)goto(self); ...
    'StarGo_STOP',       @(src,evnt)stop(self); ...
    'StarGo_sync',       @(src,evnt)align(self); ...
    'StarGo_zoom_in',    @(src,evnt)zoom(self,'in'); ...
    'StarGo_zoom_out',   @(src,evnt)zoom(self,'out'); ...
    'StarGo_zoom_guide',   @(src,evnt)zoom(self,1); ...
    'StarGo_zoom_center',  @(src,evnt)zoom(self,2); ...
    'StarGo_zoom_find',    @(src,evnt)zoom(self,3); ...
    'StarGo_zoom_max',     @(src,evnt)zoom(self,4); ...
    'Home_set',            @(src,evnt)home(self,'set'); ...
    'Home_goto',           @(src,evnt)home(self); ...
    'Track_sidereal',      @(src,evnt)write(self,'set_tracking_sidereal'); ...
    'Track_sun',           @(src,evnt)write(self,'set_tracking_solar'); ...
    'Track_moon',          @(src,evnt)write(self,'set_tracking_lunar'); ...
    'Track_none',          @(src,evnt)write(self,'set_tracking_none'); ...
    'Park_set',            @(src,evnt)park(self,'set'); ...
    'Park_goto',           @(src,evnt)park(self,'goto'); ...
    'Park_unpark',         @(src,evnt)unpark(self); ...
    'StarGo_reset',        @(src,evnt)start(self); ...
    'View_Update',         @(src,evnt)getstatus(self,'full'); ...
    'View_SkyMap',         @(src,evnt)web(self); ...
    'View_Location',       ''; ...
    'View_Help',           @(src,evnt)help(self); ...
    'View_About',          @(src,evnt)about(self) },
