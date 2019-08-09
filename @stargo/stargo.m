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
    UTCoffset = 2;
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
      cmd = strcmp(self, cmd);  % identify command, as a struct array
      cout = '';
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
      %   The t0 is [year month day hour min sec] as obtained from clock, without 
      %   subtracting UTCoffset to hours.
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
      if strcmp(t0, 'now')
        % using UTCoffset allows to compute properly the Julian Day from Stellarium
        fprintf('Date (local)                       %s\n', datestr(t0));
        t0 = clock; t0(4) = t0(4) - self.UTCoffset;
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
      if     strcmp(option, 'set'), option = 'set_park_pos';
      elseif strcmp(option, 'get'), option = 'get_park'; end
      ret = queue(self, option);
      if strcmp(option,'park')
        if ~strcmp(self.status, 'PARKED') notify(self, 'moving'); end
      elseif strcmp(option,'unpark')
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
      if     strcmp(option, 'set'), option = 'set_home_pos';
      elseif strcmp(option, 'get'), option = 'get_park'; end
      if strcmp(option, 'set_home_pos')
        ret = time(self, 'now', 'home');
        ret = [ ret queue(self, ':X351') ]; 
      else
        if strcmp(option,'home')
          if ~strcmp(self.status, 'HOME') notify(self, 'moving'); end
        end
        ret = queue(self, option);
      end
      disp([ '[' datestr(now) '] ' mfilename '.home: ' ' returned ' ret ]);
      getstatus(self);
    end % home
    
    function align(self)
      % ALIGN synchronise current location with last target (sync).
      sync(self);
    end % align
    
    function sync(self)
      % SYNC synchronise current location with last target.
      if isempty(target_name)
        disp([ mfilename ': WARNING: can not sync before defining a target with GOTO' ]);
        return
      end
      write(self, 'sync');
      disp([ '[' datestr(now) '] ' mfilename '.sync: OK' ]);
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
      %   ZOOM(s, level) sets the zoom level (1-4)
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
      elseif strcmp(level, 'in')
        level = current_level-1; % slower speed
      elseif strcmp(level, 'out')
        level = current_level+1; % faster
      elseif ischar(level)
        level=find(strcmp(level, levels));
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
        if strcmp(lower(nsew),'stop') stop(self); return; end
        index= find(lower(nsew(1)) == 'nsew');
        dirs = {'north','south','east','west'};
        if isempty(index), return; end
      end
      if strcmp(msec, 'pulse')
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
      if isempty(target_name)
        target_name = [ 'RA' sprintf('_%d', self.target_ra) ' DEC' sprintf('_%d', self.target_dec) ];
      end
      self.target_name=target_name;
      if ~isempty(h1) || ~isempty(h2)
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
      z0 = zoom(self);
      ra = self.ra_deg;
      dec= self.dec_deg;
      disp[ mfilename ': Calibrating... do not interrupt (takes 10 secs).' ]);
      stop(self);
      for z=1:4
        zoom(self, z);
        move(self, 'n'); move(self, 'e');
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
      end
      % restore current zoom level
      zoom(self, z0);
      % move back to initial location
    end % calibrate
    
    function shift(self, delta_ra, delta_dec)
      % SHIFT moves the mount by a given amount on both axes. The target is kept.
      %   SHIFT(s, delta_ra, delta_dec) moves the mount by given values in [deg]
      %   The values are added to the current coordinates.
      %
      %   This operation should be avoided close to the Poles, nor to meridian.
      if nargin < 2, delta_ra  = []; end
      if nargin < 2, delta_dec = []; end
      if any(strcmp(delta_ra,{'stop','abort'})) stop(self); return; end
      if all(self.private.ra_speeds==0) || all(self.private.dec_speeds==0)
        disp([ mfilename ': WARNING: First start a "calibrate" operation.' ]);
        return
      end
      if ~isempty(self.private.shift_ra) || ~isempty(self.private.shift_dec)
        disp([ mfilename ': WARNING: a shift is already on-going. Wait for its end or abort it with "stop".' ]);
        return
      end
      
      % determine shift target
      if isnumeric(delta_ra) && numel(delta_ra) == 1
        self.private.shift_ra = self.ra_deg + delta_ra;
      end
      if isnumeric(delta_dec) && numel(delta_dec) == 1
        self.private.shift_dec = self.dec_deg + delta_dec;
      end
      % bound target values: this avoids passing bounds which will bring issues
      if ~isempty(self.private.shift_ra)
        self.private.shift_ra = max([ 0 self.private.shift_ra   ]);
        self.private.shift_ra = min([ self.private.shift_ra 360 ]);
        self.private.shift_zoom = zoom(self);
      end
      if ~isempty(self.private.shift_dec)
        self.private.shift_dec= max([ -90 self.private.shift_dec]);
        self.private.shift_dec= min([ self.private.shift_dec 90 ]);
        self.private.shift_zoom = zoom(self);
      end
      % the auto update will handle the move (calling update_shift)
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
                 '<a href="matlab:disp(' iname ');">more...</a>)' ];
      end
      fprintf(1,'%s = %s %s\n',iname, id, char(self));
    end % display
    
    function url=help(self)
      % HELP open the Help page
      url = fullfile('file:///',fileparts(which(mfilename)),'doc','StarGo.html');
      open_system_browser(url);
    end
    
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
                '(c) E. Farhi GPL2 2019 <https://github.com/farhi/matlab-starbook>' };
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







