classdef stargo < handle
  % STARGO a class to control the Avalon StarGo for telescope mounts.
  %   The StarGo is the default controller for Avalon M-zero, M-uno, and 
  %   Linear mounts. This class can be used with the USB cable as well as with
  %   the bluetooth version.
  %
  % Initial connection:
  % ===================
  %
  % With a direct USB connection, use e.g.:
  %   sg = stargo('/dev/ttyUSB0');      % Linux
  %   sg = stargo('COM1');              % PC
  %
  % When using a Bluetooth connection, we recommend to use BlueMan.
  % Install it with e.g. 'sudo apt install blueman' or 'yum install blueman'.
  % Then assign a serial port to the connection (e.g. /dev/rfcomm0) and use:
  %   sg = stargo('/dev/rfcomm0');
  %
  % Usage:
  % =====
  % You can get the StarGo status with GETSTATUS(sg).
  %
  % (c) E. Farhi, GPL2 - version 19.06

  properties
    dev       = 'COM1'; 
    version   = '';
    longitude = 48.5;
    latitude  = 2.33;
    UTCoffset = [];
    UserData  = [];
    
    state     = [];       % detailed controller state (raw)
    private   = [];       % we put our stuff
    status    = 'INIT';
    verbose   = false;
    target_ra = [];
    target_dec= [];
    target_name = '';
    ra        = []; % as a string for display
    dec       = []; % as a string
  end % properties
  
  properties (Constant=true)
    catalogs       = getcatalogs;       % load catalogs at start
    % commands: field, input_cmd, output_fmt, description
    commands       = getcommands;
  end % shared properties        
                
  events
    gotoStart        
    gotoReached
    moving
    idle   
    updated   
  end              
  
  methods
  
    function sb = stargo(dev)
      % STARGO start communication an given device and initialize the stargo
      %   sb=STARGO(dev) specify a device, e.g. /dev/ttyUSB0
      
      if nargin
        sb.dev = dev;
      end
      
      % connect serial port
      try
        sb.private.serial = serial(sb.dev); fopen(sb.private.serial);
      catch ME
        disp([ mfilename ': ERROR: failed to connect ' sb.dev ]);
        g = getports; 
        if isempty(g), 
          disp('No connected serial port. Check cables/reconnect.')
        else disp(g); end
        return
      end
      sb.private.serial.Terminator = '#';
      
      sb.private.pulsems     = 0;
      sb.private.ra_move     = 0;
      sb.private.dec_move    = 0;
      sb.private.ra_deg      = 0;
      sb.private.dec_deg     = 0;
      sb.private.zoom        = 1; % current zoom in 1:4
      sb.private.ra_speed    = 0; % current in deg/s
      sb.private.dec_speed   = 0; % current in deg/s
      sb.private.ra_speeds   = zeros(1,4); % current in deg/s
      sb.private.dec_speeds  = zeros(1,4); % current in deg/s
      sb.private.shift_ra    = [];
      sb.private.shift_dec   = [];
      sb.private.lastUpdate  = [];
      sb.private.timer       = [];
      
      % set UTC offset from computer time
      t0 = now;
      utc = local_time_to_utc(t0);
      UTCoffset = datevec(t0) - datevec(utc);
      sb.UTCoffset = UTCoffset(4);
      
      start(sb); % make sure we start with a known configuration
      disp([ '[' datestr(now) '] ' mfilename ': ' sb.version ' connected to ' sb.dev ]);
      
      place = getplace; % location guess from the network
      if ~isempty(place) && isscalar(sb.longitude) && isscalar(sb.latitude)
        if abs(place(1)-sb.longitude) > 1 || abs(place(2)-sb.latitude) > 1
          disp([ '[' datestr(now) '] WARNING: ' mfilename ': the controller location ' ...
            mat2str([ sb.longitude sb.latitude ]) ' [deg] does not match that guessed from the Network ' mat2str(place) ]);
          disp('  *** Check StarGo Settings ***')
        end
      end
      
      % create the timer for auto update
      sb.private.timer  = timer('TimerFcn', @(src,evnt)getstatus(sb), ...
          'Period', 1.0, 'ExecutionMode', 'fixedDelay', ...
          'Name', mfilename);
      start(sb.private.timer);
    end % stargo
    
    % I/O stuff ----------------------------------------------------------------
    
    function cout = write(self, cmd, varargin)
      % WRITE sends a single command, does not wait for answer.
      %   WRITE(self, cmd) sends a single command asynchronously.
      %   The command can be a single serial string, or the command name,
      %   or a structure with 'send' field.
      %
      %   WRITE(self, { cmd1, cmd2 ... }) same as above with multiple commands.
      %
      %   WRITE(self, cmd, arg1, arg2, ...) same as above when a single command 
      %   requires additional arguments.
      
      if ~isvalid(self.private.serial), disp('write: Invalid serial port'); return; end
      cmd = private_strcmp(self, cmd);  % identify command, as a struct array
      cout = '';
      if ~isfield(self.private,'bufferSent') self.private.bufferSent=[]; end
      % send commands one by one
      for index=1:numel(cmd)
        argin = numel(find(cmd(index).send == '%'));
        if argin == numel(varargin) ...
          || (numel(varargin) == 1 && isnumeric(varargin{1}) && argin == numel(varargin{1}))
          c = sprintf(cmd(index).send, varargin{:});
          if self.verbose
            
            disp( [ mfilename '.write: ' cmd(index).name ' "' c '"' ]);
          end
          fprintf(self.private.serial, c); % SEND
          cout = [ cout c ];
          % register expected output for interpretation.
          if ~isempty(cmd(index).recv) && ischar(cmd(index).recv)
            self.private.bufferSent = [ self.private.bufferSent cmd(index) ]; 
          end
        else
          disp([ '[' datestr(now) '] WARNING: ' mfilename '.write: command ' cmd(index).send ...
            ' requires ' num2str(argin) ' arguments but only ' ...
            num2str(numel(varargin)) ' are given.' ]);
        end
      end
    end % write
    
    function [val, self] = read(self)
      % READ receives the output from the serial port.
      
      % this can be rather slow as there are pause calls.
      % registering output may help.
      if ~isvalid(self.private.serial), disp('read: Invalid serial port'); return; end
      
      % flush and get results back
      val = '';
      % we wait for output to be available (we know there will be something)
      t0 = clock;
      while etime(clock, t0) < 0.5 && self.private.serial.BytesAvailable==0
        pause(0.1)
      end
      % we wait until there is nothing else to retrieve
      t0 = clock;
      while etime(clock, t0) < 0.5 && self.private.serial.BytesAvailable
        val = [ val strtrim(flush(self)) ];
        pause(0.1)
      end
      % store output
      if ~isfield(self.private,'bufferRecv') self.private.bufferRecv=[]; end
      self.private.bufferRecv = strtrim([ self.private.bufferRecv val ]);
      % interpret results
      [p, self] = parseparams(self);
      val = strtrim(strrep(val, '#',' '));
      val = strtrim(strrep(val, '  ',' '));
      if self.verbose
        disp([ mfilename '.read ' val ]);
      end
    end % read
    
    function val = queue(self, cmd, varargin)
      % QUEUE sends a single command, returns the answer.
      if nargin == 1, val = read(self); return; end
      write(self, cmd, varargin{:});
      [val, self] = read(self);
    end % queue
        
    function delete(self)
      % DELETE close connection
      h = update_interface(self);
      if isa(self.private.timer,'timer') && isvalid(self.private.timer)
        stop(self.private.timer);
        delete(self.private.timer); 
      end
      stop(self);
      if isvalid(self.private.serial)
        fclose(self.private.serial);
      end
      close(h);
    end
    
    % GET commands -------------------------------------------------------------
    
    function v = identify(self)
      % IDENTIFY reads the StarGo identification string.
      self.version = queue(self, {'get_manufacturer','get_firmware','get_firmwaredate'});
      v = self.version;
    end % identify
    
    function val = getstatus(self, option)
      % GETSTATUS get the mount status (RA, DEC, Status)
      %   GETSTATUS(s) gets the default status. Results are stored in s.state
      %
      %   GETSTATUS(s,'full') gets the full status.

      if nargin == 1, option = ''; end
      if isempty(option), option='short'; end
      
      switch option
      case {'long','full','all'}
        list = { 'get_radec', 'get_motors', 'get_site_latitude', 'get_site_longitude', ...
          'get_st4', 'get_alignment', 'get_keypad', 'get_meridian', 'get_park', ...
          'get_system_speed_slew', 'get_autoguiding_speed', 'get_sideofpier','get_ra','get_dec', ...
          'get_meridian_forced','get_torque','get_precision','get_unkown_x1b','get_motor_status'};
        % invalid: get_localdate get_locattime get_UTCoffset get_tracking_freq
      otherwise % {'short','fast'}
        list = {'get_radec','get_motors','get_ra','get_dec','get_motor_status'};
      end
      
      % auto check for some wrong values
      if ~isfield(self.state, 'get_alignment') || ~iscell(self.state.get_alignment) ...
         || numel(self.state.get_alignment{1}) ~= 1 || ~ischar(self.state.get_alignment{1})
        list{end+1} = 'get_alignment';
      end
      if ~isfield(self.state,'get_motors') ...
        || numel(self.state.get_motors) < 2 || ~isnumeric(self.state.get_motors)
        list{end+1} = 'get_motors';
      end
      if ~isfield(self.state, 'get_motor_status') || numel(self.state.get_motor_status) < 3 ...
        || ~isnumeric(self.state.get_motor_status)
        list{end+1} = 'get_motor_status';
      end
      
      val = queue(self, list);
      notify(self,'updated');
      
      % send result to 'state' and other object fields
      update_status(self);
      
      % handle shift operation
      if ~isempty(self.private.shift_ra) || ~isempty(self.private.shift_dec)
        update_shift(self); % handle shift: start, test target values, change speed, test for done.
      end
      
      % request update of GUI
      update_interface(self);
      
      % make sure our timer is running
      if isa(self.private.timer,'timer') && isvalid(self.private.timer) && strcmp(self.private.timer.Running, 'off') 
        start(self.private.timer); 
      end
    end % getstatus
    
    % SET commands -------------------------------------------------------------
    function self=stop(self)
      % STOP stop/abort any mount move.
      
      % add:
      % X0AAUX1ST X0FAUX2ST FQ(full_abort) X3E0(full_abort) 
      write(self,{'abort','full_abort','set_stargo_off'});
      disp([ '[' datestr(now) '] ' mfilename '.stop: ABORT.' ]);
      self.private.bufferSent = [];
      self.private.bufferRecv = '';
      self.private.shift_ra  = [];
      self.private.shift_dec = [];
      notify(self, 'idle');
      pause(0.5);
      getstatus(self, 'full');
    end % stop
    
    function self=start(self)
      % START reset mount to its startup state.
      flush(self);
      identify(self);
      % normal sequence: 
      % X46r(get) X38(get_park) X22(get_autoguiding_speed) TTGM(set) TTGT(get_torque) X05(get_precision)
      % TTGHS(set) X1B TTSFG(set) X3C(get_motor_status) X3E1(set_stargo_on) Gt Gg
      queue(self, {'get_unkown_x46r','get_park','get_autoguiding_speed',':TTGM#','get_torque', ...
        'get_precision',':TTGHS#','get_unkown_x1b',':TTSFG#','get_motor_status','set_stargo_on', ...
        'get_site_latitude','get_site_longitude', ...
        'set_speed_guide','set_tracking_sidereal','set_tracking_on', ...
        'set_highprec', 'set_keypad_on', 'set_st4_on','set_system_speed_slew_fast'});
      
      self.private.bufferSent = [];
      self.private.bufferRecv = '';
      pause(0.5);
      getstatus(self, 'full');
      disp([ '[' datestr(now) '] ' mfilename '.start: Mount Ready.' ]);
    end % start
    
    function ret=time(self, t0, cmd)
      % TIME set the local sidereal time (LST)
      %   TIME(s) uses current time, and UTC offset (daylight saving)
      %   TIME(s,'now') is the same as above.
      %
      %   TIME(s,'home') is the same as above, but sets the home position/time.
      %
      %   TIME(s, t0) specifies a date/time.
      %   The t0 is [year month day hour min sec] as obtained from clock. The 
      %   given time is used as is, without subtracting UTCoffset to hours.
      if nargin == 1
        t0 = 'now';
      end
      if nargin < 3
        cmd = 'time';
      end
      switch cmd
      case {'home','set_home_pos'}
        cmd = 'set_home_pos';
      case {'park','set_park_pos','unpark'}
        cmd = 'set_sidereal_time';
      case {'time','date'}
        cmd = 'set_time';
      end
      if strcmpi(t0, 'now')
        % using UTCoffset allows to compute properly the Julian Day from Stellarium
        t0 = clock;
        fprintf('Date (local)                       %s (UTC offset %d h)\n', datestr(t0), self.UTCoffset);
        t0(4) = t0(4) - self.UTCoffset;
      end
      if ~isnumeric(t0) || numel(t0) ~= 6
        disp([ mfilename ': time: ERROR: invalid time specification. Should be e.g. t0=clock.'])
        return
      end
      if any(strcmp(cmd, {'set_home_pos','set_sidereal_time'}))
        LST = getLocalSiderealTime(self.longitude, t0);
        [h,m,s] = angle2hms(LST);
        ret = queue(self, cmd,h,m,s);
      else
        write(self, 'set_date', t0(1:3));
        write(self, 'set_time', t0(4:6));
      end
      
    end % time
    
    function ret=park(self, option)
      % PARK send the mount to a reference PARK position.
      %   PARK(s) sends the mount to its PARK position.
      %
      %   PARK(s,'park') is the same as above (send to park position).
      %
      %   PARK(s,'unpark') wakes-up mount from park position.
      %
      %   PARK(s,'set') defines park position as the current position.
      %
      %   PARK(s,'get') gets park position status, and returns '2' when PARKED, 'B' when PARKING.
      
      % park: X362 
      % unpark: X370 X32%02d%02d%02d X122 TQ
      if nargin < 2, option = 'park'; end
      if     strcmpi(option, 'set'), option = 'set_park_pos';
      elseif strcmpi(option, 'get'), option = 'get_park'; end
      ret = queue(self, option);
      if strcmpi(option,'park')
        if ~strcmpi(self.status, 'PARKED') notify(self, 'moving'); end
      elseif strcmpi(option,'unpark')
        time(self, 'now','park');
        tracking(self, 'sidereal');
      end
      disp([ '[' datestr(now) '] ' mfilename '.park: ' option ' returned ' ret ]);
    end % park
    
    function ret=unpark(self)
      %   UNPARK wakes-up mount from park position.
      ret = park(self, 'unpark');
    end % unpark
    
    function ret=home(self, option)
      % HOME send the mount to its HOME position.
      %   HOME(s) sends the mount to its HOME position.
      %
      %   HOME(s,'home') is the same as above (send to home position).
      %
      %   HOME(s,'set') sets HOME position as the current position.
      %
      %   HOME(s,'get') gets HOME position status, and returns '1' when in HOME.
      
      % set/sync home: set_site_longitude set_site_latitude X31%02d%02d%02d(set_home_pos) X351
      % goto home: X361(home) X120(set_tracking_off) X32%02d%02d%02d
      if nargin < 2, option = 'home'; end
      if     strcmpi(option, 'set'), option = 'set_home_pos';
      elseif strcmpi(option, 'get'), option = 'get_park'; end
      if strcmp(option, 'set_home_pos')
        ret = time(self, 'now', 'home');
        ret = [ ret queue(self, ':X351#') ]; 
      else
        if strcmpi(option,'home')
          if ~strcmpi(self.status, 'HOME') notify(self, 'moving'); end
        end
        ret = queue(self, option);
      end
      disp([ '[' datestr(now) '] ' mfilename '.home: ' ' returned ' ret ]);
      getstatus(self);
    end % home
    
    function align(self)
      % ALIGN synchronise current RA/DEC with last target (sync).
      sync(self);
    end % align
    
    function sync(self)
      % SYNC synchronise current RA/DEC with last target.
      if isempty(self.target_name)
        disp([ mfilename ': WARNING: can not sync before defining a target with GOTO' ]);
        return
      end
      write(self, 'sync');
      disp([ '[' datestr(now) '] ' mfilename '.sync: OK for ' self.target_name ]);
    end % sync
    
    function ms=pulse(self, ms)
    % PULSE get/set pulse length for slow moves
      if nargin < 2, ms = self.private.pulsems; 
      else 
        if ischar(ms), ms = str2double(ms); end
        if isfinite(ms)
          self.private.pulsems = ms;
        end
      end
    end % pulse
    
    function track=tracking(self, track)
    % TRACKING get/set tracking mode
    %   TRACKING(s) returns true when tracking is ON, otherwise false.
    %
    %   TRACKING(s,'on') and TRACKING(s,'off') engage/disable tracking.
    %
    %   TRACKING(s, 'lunar|sidereal|solar|none') sets tracking speed to
    %   follow the Moon, stars, the Sun, resp.
   
      if nargin < 2, track = 'get'; end
      switch lower(strtok(track))
      case 'get'
        if isfield(self.state, 'get_motor_status') && isnumeric(self.state.get_motor_status) ...
        && numel(self.state.get_motor_status) >= 2
          % [motors=OFF,DEC,RA,all_ON; track=OFF,Moon,Sun,Star; speed=Guide,Center,Find,Max]
          track = self.state.get_motor_status(2); % get track speed state
          tracks = {'off','lunar','solar','sidereal'};
          try; track = tracks{track+1}; end
        elseif isfield(self.state, 'get_alignment') && iscell(self.state.get_alignment) ...
         && self.state.get_alignment{2} == 'T', track=true; 
        elseif isfield(self.state, 'get_motors') && any(self.state.get_motors == 1) 
         track=true;
        else track=false; end
        return
      case {'on','off','lunar','sidereal','solar','none'}
        disp([ mfilename ': tracking: set to ' track ]);
        write(self, [ 'set_tracking_' lower(strtok(track)) ]);
      otherwise
        disp([ mfilename ': tracking: unknown option ' track ]);
      end
    end % tracking
    
    function flip = meridianflip(self, flip)
    % MERIDIANFLIP get/set meridian flip behaviour
    %   MERIDIANFLIP(s) returns the meridian flip mode
    %
    %   MERIDIANFLIP(s, 'auto|off|forced') sets the meridian flip as
    %   auto (on), off, and forced resp.
    
    % 0: Auto mode: Enabled and not Forced
    % 1: Disabled mode: Disabled and not Forced
    % 2: Forced mode: Enabled and Forced
      if nargin < 2, flip='get'; end
      switch lower(flip)
      case 'get'
        if self.state.get_meridian && ~self.state.get_meridian_forced
          flip = 'auto';
        elseif ~self.state.get_meridian && ~self.state.get_meridian_forced
          flip = 'off';
        elseif self.state.get_meridian && self.state.get_meridian_forced
          flip = 'forced';
        end
        return
      case {'auto','on'}
        write(self, {'set_meridianflip_on','set_meridianflip_forced_off'});
      case {'off','disabled'}
        write(self, {'set_meridianflip_off','set_meridianflip_forced_off'});
      case 'forced'
        write(self, {'set_meridianflip_on','set_meridianflip_forced_on'});
      end
    end % meridianflip
    
    function level = zoom(self, level)
      % ZOOM set (or get) slew speed. Level should be 1,2,3 or 4.
      %   ZOOM(s) returns the zoom level (slew speed)
      %
      %   ZOOM(s, level) sets the zoom level (1-4) which correspond with
      %   'guide','center','find', and 'max'.
      levels={'guide','center','find','max'};
      current_level = nan;
      if isfield(self.private, 'zoom') && isnumeric(self.private.zoom) 
        current_level = self.private.zoom;
      end
      if isfinite(current_level) && 1 <= current_level && current_level <= 4
        current_level_char = levels{current_level}; 
      else
        current_level_char = ''; 
      end
      if nargin < 2 || isempty(level)
        level=current_level;
      end
      if nargin < 2
        return
      elseif strcmpi(level, 'in')
        level = current_level-1; % slower speed
      elseif strcmpi(level, 'out')
        level = current_level+1; % faster
      elseif ischar(level)
        level=find(strcmpi(level, levels));
      end
      if ~isnumeric(level) || isempty(level), return; end
      if     level < 1, level=1;
      elseif level > 4, level=4; end
      level=round(level);
      
      z = {'set_speed_guide','set_speed_center','set_speed_find','set_speed_max'};
      if any(level == 1:4)
        write(self, z{level});
        disp([ '[' datestr(now) '] ' mfilename '.zoom: ' z{level} ]);
      end

    end % zoom
    
    % MOVES --------------------------------------------------------------------
    
    function move(self, nsew, msec)
      % MOVE slew the mount in N/S/E/W directions
      %   MOVE(s, 'dir') moves the mount in given direction. The direction can be
      %   'n', 's','e','w' for the North, South, East, West.
      %
      %   MOVE(s, 'dir stop') stops the movement in given direction, as above.
      %
      %   MOVE(s, 'dir', msec) moves the mount in given direction for given time
      %   in [msec].
      if nargin < 3, msec = 0; end
      if nargin > 1
        if strcmpi(lower(nsew),'stop') stop(self); return; end
        index= find(lower(nsew(1)) == 'nsew');
        dirs = {'north','south','east','west'};
        if isempty(index), return; end
      end
      if strcmpi(msec, 'pulse')
        msec = self.private.pulsems;
      end
      if nargin == 3 && msec > 0
        if msec > 9999, msec=9999; end
        cmd = [ 'set_pulse_' dirs{index} ];
        write(self, cmd, msec);
      elseif nargin >= 2
        if ~isempty(strfind(lower(nsew),'stop'))
          cmd = [ 'stop_slew_' dirs{index} ];
        else
          cmd = [ 'start_slew_' dirs{index} ];
        end
        write(self, cmd);
      end
      notify(self, 'moving');
    end % move
    
    function goto(self, ra, dec)
      % GOTO send the mount to given RA/DEC coordinates.
      %   GOTO(s, ra,dec) moves mount to given RA,DEC coordinates in [deg].
      %   When any of RA or DEC is empty, the other is positioned.
      %   GOTO can only be used after a HOME('set') and/or SYNC.
      %
      %   GOTO(s, [H M S], [d m s]) same as above for HH:MM:SS and dd°mm:ss
      %
      %   GOTO(s, 'hh:mm:ss','dd°mm:ss') same as above with explicit strings
      %
      %   GOTO(s, object_name) searches for object name and moves to it
      %
      % When RA and DEC are not given, a dialogue box is shown.
      if nargin < 3, dec = []; end
      if nargin < 2, ra  = []; end
      
      if ~isempty(self.private.shift_ra) || ~isempty(self.private.shift_dec)
        disp([ mfilename ': WARNING: a shift is already on-going. Wait or abort with "stop".' ]);
        return
      end
      if self.private.ra_move>1 || self.private.dec_move>1
        disp([ mfilename ': WARNING: the mount is already moving. Wait or abort with "stop".' ]);
        return
      end
      
      if isempty(ra) && isempty(dec)
        NL = sprintf('\n');
        prompt = {[ '{\bf \color{blue}Enter Right Ascension RA} ' NL ...
          '(HHhMMmSSs or HH:MM:SS or DD.dd in [deg]) ' NL ...
          'or {\color{blue}name} such as {\color{red}M 51}' ], ...
               ['{\bf \color{blue}Enter Declinaison DEC} ' NL ...
               '(DD°MM''SS" or DD°MM or DD.dd in [deg]' NL ...
               'or leave {\color{red}empty} when entering name above)' ] };
        name = 'StarGo: Goto RA/DEC: Set TARGET';
        options.Resize='on';
        options.WindowStyle='normal';
        options.Interpreter='tex';
        answer=inputdlg(prompt,name, 1, ...
          {self.ra, self.dec}, options);
        if isempty(answer), return; end
        ra=answer{1}; dec=answer{2};
      end
      target_name = '';
      % from object name
      if     ischar(ra) && strcmpi(ra, 'home'), home(self); return;
      elseif ischar(ra) && strcmpi(ra, 'park'), park(self); return;
      elseif ischar(ra) && strcmpi(ra, 'stop'), stop(self); return;
      end
      if ischar(ra) && ~any(ra(1) == '0123456789+-')
        found = findobj(self, ra);
        if ~isempty(found), ra = found; dec = ''; end
      end
      % from struct (e.g. findobj)
      if isstruct(ra) && isfield(ra, 'RA') && isfield(ra,'DEC')
        found = ra;
        dec  = found.DEC;
        ra   = found.RA;
        if isfield(found, 'NAME'), target_name = found.NAME; end
      end
      h1 = gotora (self, ra);
      h2 = gotodec(self, dec);

      if ~isempty(h1) || ~isempty(h2)
        % now we request execution of move: get_slew ":MS#"
        write(self, 'get_slew'); pause(0.25);
        if isempty(target_name)
          target_name = [ 'RA' sprintf('_%d', self.target_ra) ' DEC' sprintf('_%d', self.target_dec) ];
        end
        self.target_name=target_name;
        getstatus(self); % also flush serial out buffer
        notify(self,'gotoStart');
        disp([ mfilename ': initiating GOTO to ' self.target_name ]);
      end
    end % goto
    
    function gotoradec(self, varargin)
      % GOTORADEC send the mount to given RA/DEC coordinates.
      %   This is equivalent to GOTO
      goto(self, varargin{:});
    end % gotoradec
    
    function calibrate(self)
      % CALIBRATE measures the speed of the mount for all zoom levels
      %   CALIBRATE(s) measures the slew speed for all settings on both axes.
      %   The usual speeds on M-zeor are about [0.002 0.01 0.4 4] deg/s
      z0 = zoom(self);
      ra = self.private.ra_deg;
      dec= self.private.dec_deg;
      disp([ mfilename ': Calibrating... do not interrupt (takes 10 secs).' ]);
      stop(self); ra_dir='n'; dec_dir='e';
      for z=1:4
        zoom(self, z);
        move(self, ra_dir); move(self, dec_dir);
        pause(1); % let time to reach nominal speed
        getstatus(self);
        pause(1); % measure
        getstatus(self);
        % store current RA/DEC speed for current slew speed
        if self.private.ra_speed > 1e-3 && self.private.dec_speed > 1e-3
          self.private.ra_speeds(z)  = self.private.ra_speed;
          self.private.dec_speeds(z) = self.private.dec_speed;
        end
        stop(self);
        if z==3, ra_dir='s'; dec_dir='w'; end
      end
      % restore current zoom level
      zoom(self, z0);
      disp([ mfilename ': Calibration done.' ]);
      % move back to initial location
    end % calibrate
    
    function shift(self, delta_ra, delta_dec)
      % SHIFT moves the mount by a given amount on both axes. The target is kept.
      %   SHIFT(s, delta_ra, delta_dec) moves the mount by given values in [deg]
      %   The values are added to the current coordinates.
      %   The RA and DEC can also be given in absolute coordinates using strings
      %   as 'H:M:S' and 'DEG:M:S', as well as from vectors as [H M S] and [D M S].
      %   This move does not change the target defined with GOTO.
      %
      %   This operation should be avoided close to the Poles (DEG=+/-90), and 
      %   to the meridian (RA=0 and 24h/360deg).
      if nargin < 2, delta_ra  = []; end
      if nargin < 3, delta_dec = []; end
      if any(strcmpi(delta_ra,{'stop','abort'})) stop(self); return; end
      if all(self.private.ra_speeds==0) || all(self.private.dec_speeds==0)
        disp([ mfilename ': WARNING: First start a "calibrate" operation.' ]);
        return
      end
      if ~isempty(self.private.shift_ra) || ~isempty(self.private.shift_dec)
        disp([ mfilename ': WARNING: a shift is already on-going. Wait or abort with "stop".' ]);
        return
      end
      if self.private.ra_move>1 || self.private.dec_move>1
        disp([ mfilename ': WARNING: the mount is already moving. Wait or abort with "stop".' ]);
        return
      end
      if ischar(delta_ra),  delta_ra  = repradec(delta_ra);  end
      if ischar(delta_dec), delta_dec = repradec(delta_dec); end
      
      % determine shift target: from vector [3] in HH:MM:SS and DEG:MM:SS
      if isnumeric(delta_ra) && numel(delta_ra) == 3 % [h m s]
        delta_ra = hms2angle(delta_ra(1),delta_ra(2),delta_ra(3))*15;
        delta_ra = delta_ra - self.private.ra_deg;
      end
      if isnumeric(delta_dec) && numel(delta_dec) == 3 % [deg m s]
        delta_dec = hms2angle(delta_dec(1),delta_dec(2),delta_dec(3));
        delta_dec = delta_dec - self.private.dec_deg;
      end
      % determine shift target: from scalar (deg)
      if isnumeric(delta_ra) && numel(delta_ra) == 1
        self.private.shift_ra = self.private.ra_deg + delta_ra;
      end
      if isnumeric(delta_dec) && numel(delta_dec) == 1
        self.private.shift_dec = self.private.dec_deg + delta_dec;
      end
      if ~isempty(self.private.shift_ra) || ~isempty(self.private.shift_dec)
        self.private.shift_zoom  = zoom(self); % store initial zoom level
      end
      % bound target values: this avoids passing bounds which will bring issues
      if ~isempty(self.private.shift_ra)
        self.private.shift_ra = max([ 0 self.private.shift_ra   ]);
        self.private.shift_ra = min([ self.private.shift_ra 360 ]);
        self.private.shift_delta_ra = 0;
      end
      if ~isempty(self.private.shift_dec)
        self.private.shift_dec= max([ -90 self.private.shift_dec]);
        self.private.shift_dec= min([ self.private.shift_dec 90 ]);
        self.private.shift_delta_dec = 0;
      end
      % the auto update will handle the move (calling update_shift)
      [h1,m1,s1] = angle2hms(self.private.shift_ra,  'hours');
      [h2,m2,s2] = angle2hms(self.private.shift_dec, 'from deg');
      disp(sprintf('%s: shift: moving to RA=%d:%d:%.1f [%f deg] ; DEC=%d*%d:%.1f [%f deg]', ...
        mfilename, h1,m1,s1, self.private.shift_ra, h2,m2,s2, self.private.shift_dec));
    end % shift
    
    % GUI and output commands --------------------------------------------------
    
    function c = char(self)
      c = [ 'RA=' self.ra ' DEC=' self.dec ' ' self.status ];
      if ~strncmp(self.target_name,'RA_',3)
        c = [ c ' ' self.target_name ];
      end
    end % char
    
    function display(self)
      % DISPLAY display StarBook object (short)
      
      if ~isempty(inputname(1))
        iname = inputname(1);
      else
        iname = 'ans';
      end
      if isdeployed || ~usejava('jvm') || ~usejava('desktop') || nargin > 2, id=class(self);
      else id=[  '<a href="matlab:doc ' class(self) '">' class(self) '</a> ' ...
                 '(<a href="matlab:methods ' class(self) '">methods</a>,' ...
                 '<a href="matlab:plot(' iname ');">plot</a>,' ...
                 '<a href="matlab:getstatus(' iname ',''full''); disp(' iname '.state);">state</a>,' ...
                 '<a href="matlab:disp(' iname ');">more...</a>)' ];
      end
      fprintf(1,'%s = %s %s\n',iname, id, char(self));
    end % display
    
    function url=help(self)
      % HELP open the Help page
      url = fullfile('file:///',fileparts(which(mfilename)),'doc','StarGo.html');
      open_system_browser(url);
    end
    
    function location(self)
      % LOCATION show the current GPS location on a Map
      url = sprintf('https://maps.google.fr/?q=%f,%f', self.latitude, self.longitude);
      % open in system browser
      open_system_browser(url);
    end % location
    
    function about(self)
      try
        im = imread(fullfile(fileparts(which(mfilename)),'doc','stargo.jpg'));
      catch
        im = '';
      end
      msg = { [ 'StarGO ' self.version ], ...
                'A Matlab interface to control an Avalon StarGO board.', ...
                char(self), ...
                [ 'On ' self.dev ], ...
                evalc('disp(self.state)'), ...
                '(c) E. Farhi GPL2 2019 <https://github.com/farhi/matlab-stargo>' };
      if ~isempty(im)
        msgbox(msg,  'About StarGO', 'custom', im);
      else
        helpdlg(msg, 'About StarGO');
      end
    end % about
    
    function h = plot(self)
      % PLOT display main StarGo GUI 
      h = build_interface(self);
      figure(h); % raise
      update_interface(self);
    end % plot
    
    function url = web(self, url)
      % WEB display the starbook RA/DEC target in a web browser (sky-map.org)
      self.getstatus;
      if nargin < 2
        url = sprintf([ 'http://www.sky-map.org/?ra=%f&de=%f&zoom=%d' ...
        '&show_grid=1&show_constellation_lines=1' ...
        '&show_constellation_boundaries=1&show_const_names=0&show_galaxies=1' ], ...
        self.private.ra_deg/15, self.private.dec_deg, 9-self.private.zoom*2);
      end
      % open in system browser
      open_system_browser(url);
    end % web
    
    function config = settings(self, fig, config0)
      % SETTINGS display a dialogue to set board settings
      %  SETTINGS(s) display a dialogue to set mount configuration

      config = [];
      if nargin == 1
        config = settings_dialogue(self);
      elseif isstruct(config0)
        config = settings_apply(self, fig, config0);
      end
      
    end % settings
    
    function config = inputdlg(self, varargin)
      % INPUTDLG display a dialogue to set board settings, same as SETTINGS
      config = settings(self, varargin{:});
    end % inputdlg
    
    function t = uitable(self)
      % UITABLE display all available commands as a Table
      f = figure('Name', [ mfilename ': Available commands' ]);
      commands = { self.commands.name ; self.commands.send ; self.commands.recv ; self.commands.comment };
      t = uitable('ColumnFormat',{'char','char','char','char'}, 'Data', commands'); drawnow;
      cnames={'Alias','Send','Receive','Description'};
      
      set(t, 'Units','normalized','Position',[ 0 0 1 1 ], ...
        'ColumnName',cnames,'ColumnWidth','auto');
    end % uitable
        
    
    % Other commands -----------------------------------------------------------
    
    function found = findobj(self, name)
      % FINDOBJ find a given object in catalogs. Select it.
      %   id = findobj(sc, name) search for a given object and return ID
      catalogs = fieldnames(self.catalogs);
      found = [];
      
      % check first for name without separator
      if ~any(name == ' ')
        [n1,n2]  = strtok(name, '0123456789');
        found = findobj(self, [ n1 ' ' n2 ]);
        if ~isempty(found) return; end
      end
      namel= strtrim(lower(name));
      for f=catalogs(:)'
        catalog = self.catalogs.(f{1});
        if ~isfield(catalog, 'MAG'), continue; end
        NAME = lower(catalog.NAME);
        NAME = regexprep(NAME, '\s*',' ');
        % search for name
        index = find(~cellfun(@isempty, strfind(NAME, [ ';' namel ';' ])));
        if isempty(index)
        index = find(~cellfun(@isempty, strfind(NAME, [ namel ';' ])));
        end
        if isempty(index)
        index = find(~cellfun(@isempty, strfind(NAME, [ ';' namel ])));
        end
        if isempty(index)
        index = find(~cellfun(@isempty, strfind(NAME, [ namel ])));
        end
        if ~isempty(index)
          found.index   = index(1);
          found.catalog = f{1};
          found.RA      = catalog.RA(found.index);
          found.DEC     = catalog.DEC(found.index);
          found.MAG     = catalog.MAG(found.index);
          found.TYPE    = catalog.TYPE{found.index};
          found.NAME    = catalog.NAME{found.index};
          found.DIST    = catalog.DIST(found.index);
          break;
        end
      end

      if ~isempty(found)
        disp([ mfilename ': Found object ' name ' as: ' found.NAME ]);
        [h1,m1,s1] = angle2hms(found.RA,  'hours');
        [h2,m2,s2] = angle2hms(found.DEC, 'from deg');
        disp(sprintf('  RA=%d:%d:%.1f [%f deg] ; DEC=%d*%d:%.1f [%f deg]', ...
          h1,m1,s1, found.RA, h2,m2,s2, found.DEC));
        if found.DIST > 0
          disp(sprintf('  %s: Magnitude: %.1f ; Type: %s ; Dist: %.3g [ly]', ...
            found.catalog, found.MAG, found.TYPE, found.DIST*3.262 ));
        else
          disp(sprintf('  %s: Magnitude: %.1f ; Type: %s', ...
            found.catalog, found.MAG, found.TYPE ));
        end
      else
        disp([ mfilename ': object ' name ' was not found.' ])
      end
    end % findobj

  end % methods
  
end % classdef


% ------------------------------------------------------------------------------
% private (can not be moved into /private)
% ------------------------------------------------------------------------------

function catalogs = getcatalogs
  % GETCATALOGS load catalogs for stars and DSO.

  % stored here so that they are not loaded for further calls
  persistent loaded_catalogs  
  
  if ~isempty(loaded_catalogs)
    catalogs = loaded_catalogs; 
    return
  end
  
  % load catalogs: objects, stars
  disp([ mfilename ': Welcome ! Loading Catalogs:' ]);
  catalogs = load(mfilename);
  
  % display available catalogs
  for f=fieldnames(catalogs)'
    name = f{1};
    if ~isempty(catalogs.(name))
      num  = numel(catalogs.(name).RA);
      if isfield(catalogs.(name), 'Description')
        desc = catalogs.(name).Description;
      else desc = ''; end
      disp([ mfilename ': ' name ' with ' num2str(num) ' entries.' ]);
      disp([ '  ' desc ])
    end
  end

  loaded_catalogs = catalogs;
end % getcatalogs

function c = getcommands

  % list of commands to be used with StarGo, derived from LX200 protocol.
  commands = { ...                   
    'get_alignment',                'GW',         '%c%c%1d', 'query Scope alignment status(mt,tracking,nb_alignments)';
    'get_firmwaredate',             'GVD',        'd%s','query firmware date'; 
    'get_firmware',                 'GVN',        '%f','query firmware version';
    'get_ra',                       'GR',         '%d:%d:%d','query RA  (h:m:s)'; 
    'get_dec',                      'GD',         '%d*%d:%d','query DEC (d:m:s)'; 
    'get_keypad',                   'TTGFr',      'vr%1d','query Keypad status(0,1)';     
    'get_manufacturer',             'GVP',        '%s','manufacturer';
    'get_meridian_forced',          'TTGFd',      'vd%1d','query meridian flip forced(TF)';
    'get_meridian',                 'TTGFs',      'vs%d','query meridian flip(TF)';  
    'get_motors',                   'X34',        'm%1d%1d','query motors state(0:5==stop,tracking,accel,decel,lowspeed,highspeed)'; 
    'get_park',                     'X38',        'p%s','query tracking state(0=unparked,1=homed,2=parked,A=slewing,B=slewing2park)';   
    'get_precision',                'X05',        '%s','query precision, returns "U"';
    'get_radec',                    'X590',       'RD%8d%8d','query RADEC(RA*1e6,DEC*1e5) in deg';
    'get_sideofpier',               'X39',        'P%c','query pier side(X=unkown,E=east2east,W=east2west)';  
    'get_site_latitude',            'Gt',         '%dt%d:%d','query Site Latitude';  
    'get_site_longitude',           'Gg',         '%dg%d:%d','query Site Longitude';     
    'get_slew',                     'MS',         '%d','query slewing state(0=slewing) and start move';     
    'get_autoguiding_speed',        'X22',        '%db%d','query autoguiding speeds(ra,dec)';   
    'get_system_speed_slew',        'TTGMX',      '%da%d','query slewing speed(xx=6,8,9,12,yy)';    
    'get_st4',                      'TTGFh',      'vh%1d','query ST4 status(TF)';  
    'get_torque',                   'TTGT',       't%3d','query motor torque (x=50-150 in %)';
    'get_unkown_x1b',               'X1B',        'w%2d','query X1B, e.g. returns "w01"';
    'get_unkown_x29',               'X29',        'TCB=%d.','query X29, returns TCB';
    'get_unkown_x461',              'X461',       'c%1d','query X461, e.g. "c1"';
    'get_unkown_x46r',              'X46r',       'c%1d','query X46r, e.g. "c1"';
    'get_motor_status',             'X3C',        ':Z1%1d%1d%1d','query motor status [motors=OFF,DEC,RA,all_ON;track=OFF,Moon,Sun,Star;speed=Guide,Center,Find,Max]';
    'set_altaz',                    'AA',         '',     'set to alt/az mode';
    'set_autoguiding_speed_dec',    'X21%02d',    '',     'set auto guiding speed on DEC (xx for 0.xx %)';
    'set_autoguiding_speed_ra',     'X20%02d',    '',     'set auto guiding speed on RA (xx for 0.xx %)';
    'set_brake_ra',                 'X2B0%05d',   '',     'set Brake M.Step Value RA';
    'set_brake_dec',                'X2B1%05d',   '',     'set Brake M.Step Value DEC';
    'set_date',                     'SC %02d%02d%02d','', 'set local date(mm,dd,yy)(0)';
    'set_dec',                      'Sd %+03d*%02d:%02d', '','set DEC(dd,mm,ss)';
    'set_equatorial',               'AP',         '','set mount to equatorial mode';
    'set_guiding_speed_dec',        'X21%2d',     '','set DEC speed(dd percent)';
    'set_guiding_speed_ra',         'X20%2d',     '','set RA speed(dd percent)';
    'set_highprec',                 'U',          '','switch to high precision';
    'set_hemisphere_north',         'TTHS0',      '','set North hemisphere';
    'set_hemisphere_south',         'TTHS1',      '','set South hemisphere';
    'set_home_pos',                 'X31%02d%02d%02d','','sync home position (LST in HH MM SS)';
    'set_keypad_off',               'TTSFr',      '','disable keypad';
    'set_keypad_on',                'TTRFr',      '','enable keypad';
    'set_meridianflip_forced_off',  'TTRFd',      '','disable meridian flip forced';  
    'set_meridianflip_forced_on',   'TTSFd',      '','enable meridian flip forced';     
    'set_meridianflip_off',         'TTRFs',      '','disable meridian flip';     
    'set_meridianflip_on' ,         'TTSFs',      '','enable meridian flip';    
    'set_mount_gear_ratio',         'TTSM%1d',    '','set mount model (x=1-9 for M0,576,Linear,720,645,1440,Omega,B230,Custom)'; 
    'set_mount_gear_ra',            'X2C0%7d',    '','set mount gear ratio RA (x=RA*1000)'; 
    'set_mount_gear_dec',           'X2C1%7d',    '','set mount gear ratio DEC (x=DEC*1000)'; 
    'set_park_pos',                 'X352',       '','sync park position (0)';
    'set_polar_led',                'X07%1d',     '','set the polar LED level in 10% (x=0-9)';
    'set_pulse_east',               'Mge%04d',    '','move east for (t msec)';
    'set_pulse_north',              'Mgn%04d',    '','move north for (t msec)';
    'set_pulse_south',              'Mgs%04d',    '','move south for (t msec)';
    'set_pulse_west',               'Mgw%04d',    '','move west for (t msec)';
    'set_ra',                       'Sr %02d:%02d:%02d', '','set RA(hh,mm,ss)';
    'set_ramp_radec',               'X06%03d%03d','','set Ramp Acceleration Value (ra,dec, e.g. 3 or 5)';
    'set_reverse_radec',            'X1A%1d%1d',  '','set RA/DEC reverse direction';
    'set_sidereal_time',            'X32%02d%02d%02d','','set local sidereal time(hh,mm,ss) at park';
    'set_site_latitude',            'St%+03d*%02d:%02d#Gt', '','set site latitude(dd,mm,ss)'; 
    'set_site_longitude',           'Sg%+04d*%02d:%02d#Gg', '','set site longitude(dd,mm,ss)'; 
    'set_speed_guide',              'RG',         '','set slew speed guide (1/4)';
    'set_speed_center',             'RC',         '','set slew speed center (2/4)';     
    'set_speed_find',               'RM',         '','set slew speed find (3/4)';     
    'set_speed_max',                'RS',         '','set slew speed max (4/4)';     
    'set_st4_off',                  'TTRFh',      '','disable ST4 port';
    'set_st4_on',                   'TTSFh',      '','enable ST4 port';
    'set_stargo_on',                'X3E1',       '','set stargo on';
    'set_stargo_off',               'X3E0',       '','set stargo off';
    'set_system_speed_center_2',    'X03007:0010','','set system center speed to 2';
    'set_system_speed_center_3',    'X0300510010','','set system center speed to 3';
    'set_system_speed_center_4',    'X03003=0010','','set system center speed to 4';
    'set_system_speed_center_6',    'X0300280010','','set system center speed to 6 (default)';
    'set_system_speed_center_8',    'X03001>0010','','set system center speed to 8';
    'set_system_speed_center_10',   'X0300180010','','set system center speed to 10';
    'set_system_speed_guide_10',    'X0300280031','','set system guide speed to 10';
    'set_system_speed_guide_15',    'X0300280020','','set system guide speed to 15';
    'set_system_speed_guide_20',    'X0300280018','','set system guide speed to 20';
    'set_system_speed_guide_30',    'X0300280010','','set system guide speed to 30 (default)';
    'set_system_speed_guide_50',    'X030028000','', 'set system guide speed to 50';
    'set_system_speed_guide_75',    'X0300280006','','set system guide speed to 75';
    'set_system_speed_guide_100',   'X0300280005','','set system guide speed to 100';
    'set_system_speed_guide_150',   'X0300280003','','set system guide speed to 150';
    'set_system_speed_slew_low',         'TTMX0606',   '','set system slew speed low (1/4)';     
    'set_system_speed_slew_medium',      'TTMX0808',   '','set system slew speed medium (2/4)'; 
    'set_system_speed_slew_fast',        'TTMX0909',   '','set system slew speed fast (3/4) (default)';
    'set_system_speed_slew_fastest',     'TTMX1212',   '','set system slew speed max (4/4)';       
    'set_time',                     'SL %02d:%02d:%02d', '0','set local time(hh,mm,ss)';
    'set_tracking_lunar',           'X123#:TL',         '','set tracking lunar';
    'set_tracking_none',            'TM',         '','set tracking none';
    'set_tracking_off',             'X120',       '','disable tracking';     
    'set_tracking_on',              'X122',       '','enable tracking';     
    'set_tracking_rate_ra',         'X1E%04d',    '','set tracking rate on RA  (xxxx=1000+-500:500)';
    'set_tracking_rate_dec',        'X1F%04d',    '','set tracking rate on DEC (xxxx=1000+-500:500)';
    'set_tracking_sidereal',        'X123#:TQ',         '','set tracking sidereal';
    'set_tracking_solar',           'X123#:TS',         '','set tracking solar';
    'set_torque',                   'TTT%03d',    '','set motor torque (e.g. x=50 or 70, BEWARE)';
    'set_UTCoffset',                'SG %+03d',   '','set UTC offset(hh)';
    'abort',                        'Q',          '','abort current move'; 
    'full_abort',                   'FQ',         '','full abort/stop';
    'home',                         'X361',       '','send mount to home (pA)';
    'park',                         'X362',       '','send mount to park (pB)';
    'start_slew_east',              'Me',         '','start to move east';
    'start_slew_north'              'Mn',         '','start to move north';     
    'start_slew_south'              'Ms',         '','start to move south';   
    'start_slew_west',              'Mw',         '','start to move west';
    'stop_slew_east',               'Qe',         '','stop to move east';
    'stop_slew_north',              'Qn',         '','stop to move north';
    'stop_slew_south',              'Qs',         '','stop to move south';
    'stop_slew_west',               'Qw',         '','stop to move west';
    'sync',                         'CM',         '','sync (align), i.e. indicate we are on last target';
    'unpark',                       'X370',       '','wake up from park (p0)';  
    'shutdown',                     'XFF',        '','shut down StarGo completely (loose connection)';
    'get_localdate',                'GC',         '%d%c%d%c%d', 'invalid:query Local date(mm,dd,yy)';
    'get_locattime',                'GL',         '%2d:%2d:%2d','invalid:query local time(hh,mm,ss)';
    'get_tracking_freq',            'GT',         '%f','invalid:query tracking frequency';
    'get_UTCoffset',                'GG',         '%f','invalid:query UTC offset';
  };
  % other unkown commands when loading MCF: 
  % X280300 returns 0
  % X280303 returns 0
  % TTSMs0??>:><;8 returns 0
  % TTSMs1????;?<5 returns 0
  % TTGM
  % TTGHS
  % TTSFG
  c = [];
  for index=1:size(commands,1)
    this = commands(index,:);
    f.name   = this{1};
    f.send   = [ ':' this{2} '#' ];
    f.recv   = this{3};
    f.comment= this{4};
    c = [ c f ];
  end
  
end % getcommands




