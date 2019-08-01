function h = build_interface(self)

  % check if window is already opened
  h = [ findall(0, 'Tag','StarGo_window') findall(0, 'Tag','StarGo_GUI') ];
  if ~isempty(h)
    set(0,'CurrentFigure', h); % make it active
  else  
    % else create
    h = openfig('stargo.fig');
    
    % uicontrols
    Callbacks = { ...
    'stargo_status' @(src,evnt)getstatus(self,'full'); ...
    'stargo_s'      @(src,evnt)move(self, 's','pulse'); ...
    'stargo_n'      @(src,evnt)move(self, 'n','pulse'); ...
    'stargo_e'      @(src,evnt)move(self, 'e','pulse'); ...
    'stargo_w'      @(src,evnt)move(self, 'w','pulse'); ...
    'stargo_stop'   @(src,evnt)stop(self); ...
    'stargo_zoom'   @(src,evnt)zoom(self, get(gcbo, 'Value')); ...
    'stargo_ra'     @(src,evnt)goto(self, get(gcbo, 'String'), ''); ...
    'stargo_dec'    @(src,evnt)goto(self, '', get(gcbo, 'String')); ...
    'stargo_pulse'  @(src,evnt)pulse(self, get(gcbo, 'String')); ...
    };
    
    build_callbacks(self, h, Callbacks);
    
    % menus
    Callbacks = { ...
      'view_about',             @(src,evnt)about(self); ...
      'view_help',              @(src,evnt)help(self); ...
      'view_location',          ''; ...
      'view_skymap',            @(src,evnt)web(self); ...
      'view_auto_update'        ''; ...
      'view_update',            @(src,evnt)getstatus(self,'full'); ...
      'navigate_settings',      ''; ...
      'navigate_reset',         @(src,evnt)start(stop(self)); ...
      'navigate_sync',          @(src,evnt)sync(self); ...
      'navigate_stop',          @(src,evnt)stop(self); ...
      'navigate_goto',          @(src,evnt)goto(self); ...
      'navigate_track_none',    @(src,evnt)write(self,'set_tracking_off'); ...
      'navigate_track_moon',    @(src,evnt)write(self,'set_tracking_lunar'); ...
      'navigate_track_sun',     @(src,evnt)write(self,'set_tracking_solar'); ...
      'navigate_track_sidereal',@(src,evnt)write(self,'set_tracking_sidereal'); ...
      'navigate_park_unpark',   @(src,evnt)unpark(self); ...
      'navigate_park_goto',     @(src,evnt)park(self); ...
      'navigate_park_set'       @(src,evnt)park(self,'set'); ...
      'navigate_home_goto',     @(src,evnt)home(self); ...
      'navigate_home_set',      @(src,evnt)home(self,'set'); ...
      'navigate_zoom_max',      @(src,evnt)zoom(self,4); ...
      'navigate_zoom_find',     @(src,evnt)zoom(self,3); ...
      'navigate_zoom_center',   @(src,evnt)zoom(self,2); ...
      'navigate_zoom_guide',    @(src,evnt)zoom(self,1); ...
      'navigate_zoom_out',      @(src,evnt)zoom(self,'out'); ...
      'navigate_zoom_in',       @(src,evnt)zoom(self,'in') };
    
    build_callbacks(self, h, Callbacks);
  end
    
% ------------------------------------------------------------------------------

function build_callbacks(self, h, Callbacks)
  for index=1:size(Callbacks,1)
    obj = findobj(h, 'Tag', Callbacks{index,1});
    if ~isscalar(obj)
      disp([ mfilename ': Invalid Tag ' Callbacks{index,1} ' in GUI' ])
    elseif ~isempty(Callbacks{index,2})
      set(obj, 'Callback', Callbacks{index,2})
    end
  end

