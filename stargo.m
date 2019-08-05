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
    status    = 'INIT';
    verbose   = false;
    target_ra = [];
    target_dec= [];
    target_name = '';
    ra        = [];
    dec       = [];
  end % properties
  
  properties(Access=private)
    timer      = [];       % the current Timer object which sends a getstatus regularly
    bufferSent = [];
    bufferRecv = '';
    start_time = datestr(now);
    serial     = [];       % the serial object
  end % properties
  
  properties (Constant=true,Access=private)
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
      sb.start_time = now;
      
      % connect serial port
      try
        sb.serial = serial(sb.dev); fopen(sb.serial);
      catch ME
        disp([ mfilename ': ERROR: failed to connect ' sb.dev ]);
        g = getports; 
        if isempty(g), 
          disp('No connected serial port. Check cables/reconnect.')
        else disp(g); end
        return
      end
      sb.serial.Terminator = '#';
      sb.state.pulsems     = 0;
      sb.state.ra_move     = 0;
      sb.state.dec_move    = 0;
      sb.state.zoom        = 1;
      
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
      sb.timer  = timer('TimerFcn', @(src,evnt)getstatus(sb), ...
          'Period', 1.0, 'ExecutionMode', 'fixedDelay', ...
          'Name', mfilename);
      start(sb.timer);
    end % stargo
    
    % I/O stuff ----------------------------------------------------------------
    
    function out = strcmp(self, in)
      % STRCMP identify commands within available ones.
      %   STRCMP(self, CMD) searches for CMD in available commands. CMD can be
      %   given as a single serial command. The return value is a structure.
      %
      %   STRCMP(self, { 'CMD1' 'CMD2' ... }) does the same with an array as input.
      if isstruct(in) && isfield(in,'send'), out = in; return;
      elseif isnumeric(in), out = self.commands(in); return;
      elseif ~ischar(in) && ~iscellstr(in)
        error([ '[' datestr(now) '] ERROR: ' mfilename '.strcmp: invalid input type ' class(in) ]);
      end
      in = cellstr(in);
      out = [];
      for index = 1:numel(in)
        this_in = in{index};
        if this_in(1) == ':', list = { self.commands.send };
        else                  list = { self.commands.name }; end
        tok = find(strcmpi(list, this_in));
        if numel(tok) == 1
          out = [ out self.commands(tok) ];
        else
          disp([ '[' datestr(now) '] WARNING: ' mfilename '.strcmp: can not find command ' this_in ' in list of available ones.' ]);
          out1.name = 'custom command';
          out1.send = this_in;
          out1.recv = '';
          out1.comment = '';
          out = [ out out1 ];
        end
      end
      
    end % strcmp
    
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
      
      if ~isvalid(self.serial), disp('write: Invalid serial port'); return; end
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
          fprintf(self.serial, c); % SEND
          cout = [ cout c ];
          % register expected output for interpretation.
          if ~isempty(cmd(index).recv) && ischar(cmd(index).recv)
            self.bufferSent = [ self.bufferSent cmd(index) ]; 
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
      if ~isvalid(self.serial), disp('read: Invalid serial port'); return; end
      
      % flush and get results back
      val = '';
      % we wait for output to be available (we know there will be something)
      t0 = clock;
      while etime(clock, t0) < 0.5 && self.serial.BytesAvailable==0
        pause(0.1)
      end
      % we wait until there is nothing else to retrieve
      t0 = clock;
      while etime(clock, t0) < 0.5 && self.serial.BytesAvailable
        val = [ val strtrim(flush(self)) ];
        pause(0.1)
      end
      % store output
      self.bufferRecv = strtrim([ self.bufferRecv val ]);
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
      if isa(self.timer,'timer') && isvalid(self.timer)
        stop(self.timer);
        delete(self.timer); 
      end
      stop(self);
      if isvalid(self.serial)
        fclose(self.serial);
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
      persistent list_all list_fast
      if nargin == 1, option = ''; end
      if isempty(option), option='short'; end
      
      switch option
      case {'long','full','all'}
        list = { 'get_radec', 'get_motors', 'get_site_latitude', 'get_site_longitude', ...
          'get_st4', 'get_alignment', 'get_keypad', 'get_meridian', 'get_park', ...
          'get_system_speed_slew', 'get_autoguiding_speed', 'get_sideofpier','get_ra','get_dec', ...
          'get_meridian_forced','get_torque','get_precision','get_unkown_x1b','get_motors_status'};
        % invalid: get_localdate get_locattime get_UTCoffset get_tracking_freq
      otherwise % {'short','fast'}
        list = {'get_radec','get_motors','get_ra','get_dec','get_motors_status'};
      end
      val = queue(self, list);
      notify(self,'updated');
      
      % transfer main controller status
      %   RA DEC stored as string for e.g. display in interfaces
      if isfield(self.state, 'get_radec') && numel(self.state.get_radec) == 2
        self.state.ra_deg  = double(self.state.get_radec(1))/1e6; % in [hours]
        self.state.dec_deg = double(self.state.get_radec(2))/1e5; % in [deg]
        [h1,m1,s1] = angle2hms(self.state.ra_deg,'deg');  % in deg
        [h2,m2,s2] = angle2hms(abs(self.state.dec_deg),'deg');
        self.state.ra_deg = self.state.ra_deg*15; % in [deg]
        if self.state.get_radec(2) < 0, sig = '-'; else sig=''; end
        self.ra  = sprintf('%d:%d:%.1f', h1,m1,s1);
        self.dec = sprintf('%c%d°%d:%.1f', sig, h2,m2,s2);
      elseif  isfield(self.state, 'get_ra') || isfield(self.state, 'get_dec')
        if isfield(self.state, 'get_ra')
          self.ra = sprintf('%d:%d:%.1f', self.state.get_ra(1), self.state.get_ra(2), self.state.get_ra(3));
        end
        if isfield(self.state, 'get_dec')
          self.dec= sprintf('%d°%d:%.1f', self.state.get_dec); % the sign is lost here
        end
      end
      
      %   motor state and mount status: get_alignment, get_park
      % 'get_alignment', 'GW', 'query Scope alignment status(mt,tracking,nb_alignments)';
      %   isTracking: self.state.get_alignment{2} == 'T'
      if ~isfield(self.state, 'get_alignment') || ~iscell(self.state.get_alignment) ...
      || ~ischar(self.state.get_alignment{1})
        disp([ '[' datestr(now) '] WARNING: ' mfilename '.getstatus: invalid get_alignment' ]);
        self.state.get_alignment = [];
      end
      % 'get_motors',    'X34','query motors state(0:5==stop,tracking,accel,decel,lowspeed,highspeed)';
      if isfield(self.state,'get_motors')
        if numel(self.state.get_motors) >= 2 && isnumeric(self.state.get_motors)
          self.state.ra_move = self.state.get_motors(1);
          self.state.dec_move= self.state.get_motors(2);
        else
          disp([ '[' datestr(now) '] WARNING: ' mfilename '.getstatus: invalid get_motors' ]);
          self.state.get_motors = [];
        end
        if any(self.state.get_motors > 1)
          self.status = 'MOVING';
        elseif any(self.state.get_motors == 1)
          self.status = 'TRACKING';
        elseif all(self.state.get_motors == 0)
          self.status = 'STOPPED';
        end
      end
      % 'get_park',      'X38','query tracking state(0=unparked,1=homed,2=parked,A=slewing,B=slewing2park)';   
      if isfield(self.state,'get_park')
        switch self.state.get_park
        case '1'
          self.status = 'HOME';
        case '2'
          self.status = 'PARKED';
        case 'A'
          self.status = 'SLEWING';
        case 'B'
          self.status = 'PARKING';
        end
      end
      % longitude/latitude
      if isfield(self.state,'get_site_longitude')
        self.longitude= hms2angle(double(self.state.get_site_longitude));
      end
      if isfield(self.state,'get_site_latitude')
        self.latitude= hms2angle(double(self.state.get_site_latitude));
      end
      
      % request update of GUI
      update_interface(self);
      % make sure our timer is running
      if isa(self.timer,'timer') && isvalid(self.timer) && strcmp(self.timer.Running, 'off') 
        start(self.timer); 
      end
    end % getstatus
    
    % SET commands -------------------------------------------------------------
    function self=stop(self)
      % STOP stop/abort any mount move.
      
      % add:
      % X0AAUX1ST X0FAUX2ST FQ(full_abort) X3E0(full_abort) 
      write(self,{'abort','full_abort','set_stargo_off'});
      disp([ '[' datestr(now) '] ' mfilename '.stop: ABORT.' ]);
      self.bufferSent = [];
      self.bufferRecv = '';
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
      % TTGHS(set) X1B TTSFG(set) X3C(get_motors_status) X3E1(set_stargo_on) Gt Gg
      queue(self, {':X46r#','get_park','get_autoguiding_speed',':TTGM#','get_torque', ...
        'get_precision',':TTGHS#','get_unkown_x1b',':TTSFG#','get_motors_status','set_stargo_on', ...
        'get_site_latitude','get_site_longitude', ...
        'set_speed_guide','set_tracking_sidereal','set_tracking_on', ...
        'set_highprec', 'set_keypad_on', 'set_st4_on','set_system_speed_slew_fast'});
      
      self.bufferSent = [];
      self.bufferRecv = '';
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
      if nargin < 2, ms = self.state.pulsems; 
      else 
        if ischar(ms), ms = str2double(ms); end
        if isfinite(ms)
          self.state.pulsems = ms;
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
        if isfield(self.state, 'get_motors_status') && isnumeric(self.state.get_motors_status)
          % [motors=OFF,DEC,RA,all_ON; track=OFF,Moon,Sun,Star; speed=Guide,Center,Find,Max]
          track = self.state.get_motors_status(2);
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
      if nargin < 2 || isempty(level)
        % [motors=OFF,DEC,RA,all_ON; track=OFF,Moon,Sun,Star; speed=Guide,Center,Find,Max]
        level = self.state.get_motors_status(3);
        try; level=levels{level+1}; end
      end
      if nargin < 2
        return
      elseif strcmp(level, 'in')
        level = level-1;      % slower speed
      elseif strcmp(level, 'out')
        level = level+1; % faster
      elseif ischar(level)
        level=find(strcmp(level, levels));
      end
      if ~isnumeric(level) || isempty(level), level=[]; return; end
      if     level < 1, level=1;
      elseif level > 4, level=4; end
      level=round(level);
      
      z = {'set_speed_guide','set_speed_center','set_speed_find','set_speed_max'};
      if any(level == 1:4)
        write(self, z{level});
        disp([ '[' datestr(now) '] ' mfilename '.zoom: ' z{level} ]);
        self.state.zoom = level;
      end

    end % zoom
    
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
        msec = self.state.pulsems;
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
      %   GOTO(sb, ra,dec) moves mount to given RA,DEC coordinates in [deg].
      %   When any or RA or DEC is empty, the other is positioned.
      %
      %   GOTO(sb, [H M S], [d m s]) same as above for HH:MM:SS and dd°mm:ss
      %
      %   GOTO(sb, 'hh:mm:ss','dd°mm:ss') same as above with explicit strings
      %
      %   GOTO(sb, object_name) searches for object name and moves to it
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
          {self.target_ra, self.target_dec}, options);
        if isempty(answer), return; end
        ra=answer{1}; dec=answer{2};
      end
      target_name = '';
      % from object name
      if     ischar(ra) && strcmp(ra, 'home'), home(self); return;
      elseif ischar(ra) && strcmp(ra, 'park'), park(self); return;
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
      end
    end % goto
    
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
        self.state.ra_deg/15, self.state.dec_deg, 9-self.state.zoom*2);
      end
      % open in system browser
      open_system_browser(url);
    end % web
    
    function config = settings(self)
      % SETTINGS display a dialogue to set board settings
      
      % pop-up choices must start with the current one
      config_meridian = {'auto','off','forced'};
      index = strcmp(strtok(config_meridian), meridianflip(self));
      config_meridian = config_meridian([ find(index) find(~index) ]);
      if tracking(self)
        config_tracking = {'on','off','sidereal (stars)','lunar','solar'};
      else
        config_tracking = {'off','on','sidereal (stars)','lunar','solar'};
      end
      config_slew={'6: low','8: medium','9: fast','12: fastest (15-18 V)'}; % from get_system_speed_slew
      config_guide={'10','15','20','30','50','75','100','150'};
      % usual initial config:
      % self.state.get_site_longitude=[2  20 0];
      % self.state.get_site_latitude=[48 52 0];
      % self.UTCoffset=2;
      % self.state.get_st4=0;
      % self.state.get_keypad=0;
      % self.state.get_system_speed_slew=[6 6];
      % self.state.get_autoguiding_speed=[30 30];
      [config, button] = settingsdlg( ...
        'title',[ mfilename ': mount settings' ], ...
        'Description',[ 'Please check/update the ' mfilename ...
                        ' configuration.' ], ...
        {'Longitude [HH MM SS]','longitude'}, num2str(self.state.get_site_longitude), ...
        {'Latitude [DD MM SS]','latitude'}, num2str(self.state.get_site_latitude), ...
        {'UTC offset (dayligh saving)','UTCoffset'}, self.UTCoffset, ...
        {'Tracking','tracking'}, config_tracking, ...
        'separator','   ', ...
        {'Meridian flip','meridianflip'}, config_meridian, ...
        {'ST4 port connected','st4'}, logical(self.state.get_st4), ...
        {'Keypad connected','keypad'}, logical(self.state.get_keypad), ...
        {'Equatorial/Alt-Az mode','mode'}, {'equatorial','altaz'}, ...
        {'Auto guiding speed [RA DEC in %, e.g. 30 stands for 0.30]','set_guiding_speed'}, num2str(self.state.get_autoguiding_speed), ...
        {'Hemisphere','hemisphere'}, {'North','South'}, ...
        {'Mount gear ratio','mount_gear_ratio'},{'1: M-zero','2: 576','3: Linear','4: 720','5: 645','6: 1440','7: Omega','8: B230'}, ...
        {'Polar LED light level [in %]','polar_led'},{'off','10','20','30','40','50','60','70','80','90'}, ...
        {'Reverse RA', 'reverse_ra'}, false, ...
        {'Reverse DEC','reverse_dec'}, true, ...
        {'System speed: center (default:6)','system_speed_center'}, {'2','3','4','6','8','10'}, ...
        {'System speed: guide (default:30)','system_speed_guide'},  {'10','15','20','30','50','75','100','150'}, ...
        {'System speed: slew (default:fast)', 'system_speed_slew'}, config_slew ...
      );
      
      if isempty(button) || strcmp(button,'cancel') return; end
      
      % check for changes
      if isfinite(config.UTCoffset)
        write(self, 'set_UTCoffset', round(config.UTCoffset));
      end
      if config.st4, write(self, 'set_st4_on');
      else           write(self, 'set_st4_off'); end
      if config.keypad, write(self, 'set_keypad_on');
      else           write(self, 'set_keypad_off'); end
      
      % send date, time, daylight saving shift.
      t0=clock; 
      write(self, 'set_date', t0(1:3));
      write(self, 'set_time', t0(4:6));
      % 'set_UTCoffset',                'SG %+03d',   '','set UTC offset(hh)';
      write(self, 'set_UTCoffset', self.UTCoffset);
      % display date/time settings
      t0(4)=t0(4)-self.UTCoffset; % allows to compute properly the Julian Day from Stellarium
      time(self, t0, 'home'); % sets LST
      time(self, t0, 'time'); % sets time and date

      tracking(self, strtok(config.tracking));
      meridianflip(self, strtok(config.meridianflip));
      
      % these do not work: the StarGo gets blocked
      config.longitude = str2num(repradec(config.longitude));
      if numel(config.longitude) == 3 && all(isfinite(config.longitude))
        write(self, 'set_site_longitude', round(config.longitude));
      end
      config.latitude = str2num(repradec(config.latitude));
      if numel(config.latitude) == 3 && all(isfinite(config.latitude))
        write(self, 'set_site_latitude', round(config.latitude))
      end
      write(self, ['set_system_speed_' strtok(config.system_speed)]);
      
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

% ------------------------------------------------------------------------------
% private functions
% ------------------------------------------------------------------------------


function [p,self] = parseparams(self)
  % PARSEPARAMS interpret output and decode it.
  recv = self.bufferRecv; p=[];
  if isempty(recv), return; end
  % cut output from serial port into separate tokens
  recv = textscan(recv,'%s','Delimiter','# ','MultipleDelimsAsOne',true);
  recv = recv{1};
  if isempty(recv), return; end
  
  % check if we have a Z1 status string in received buffer
  toremove = [];
  allSent = self.bufferSent; 
  % we search for a pattern in sent that matches the actual recieved string
  for indexR=1:numel(recv)
    if isempty(recv{indexR}), continue; end
    for indexS=1:numel(allSent)
      sent = allSent(indexS); tok = [];
      if any(indexS == toremove), continue; end
      if isempty(sent.recv), continue; end
      try
        % look for an expected output 'sent' in the actual output 'recv'
        [tok,pos] = textscan(recv{indexR}, sent.recv);
      catch ME
        continue; % pattern does not match received string. try an other one.
      end

      if ~isempty(tok) && ~any(cellfun(@isempty,tok))
        if numel(tok) == 1
          tok = tok{1};
        end
        if iscell(tok) && all(cellfun(@isnumeric, tok))
          tok = cell2mat(tok);
        elseif iscell(tok) && all(cellfun(@ischar, tok))
          tok = char(tok);
        end
        self.state.(sent.name) = tok; % store in object 'state'
        p.(sent.name)   = tok;
        toremove(end+1) = indexS; % clear this request for search
        recv{indexR}    = [];     % clear this received output as it was found
        break; % go to next received item
      end % if tok
    end % for indexS
  end % for indexR
  toremove(toremove >  numel(self.bufferSent)) = [];
  toremove(toremove <= 0) = [];
  self.bufferSent(toremove) = [];
  if ~all(cellfun(@isempty, recv))
    self.bufferRecv = sprintf('%s#', recv{:});
  else
    self.bufferRecv = '';
  end
  self.state=orderfields(self.state);
  % typical state upon getstatus:
  %            get_manufacturer: 'Avalon'
  %           get_firmware: 56.6000
  %       get_firmwaredate: 'd01122017'
  %              get_radec: [32463 1]
  %             get_motors: [1 0]
  %      get_site_latitude: [48 52 0]
  %     get_site_longitude: [2 20 0]
  %                get_st4: 1
  %          get_alignment: {'P'  'T'  [0]}
  %             get_keypad: 0
  %           get_meridian: 0
  %               get_park: '0'
  %  get_system_speed_slew: [8 8]
  %      get_autoguiding_speed: [30 30]
  %         get_sideofpier: 'X'
  %                 get_ra: [0 1 57]
  %                get_dec: [0 0 0]
  %    get_meridian_forced: 0
end % parseparams

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
    'get_firmwaredate',             'GVD',        '%s','query firmware date'; 
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
    'get_unkown_x1b',               'X1B',        '%s','query X1B, e.g. returns "w01"';
    'get_motors_status',            'X3C',        ':Z1%1d%1d%1d','query motor status [motors=OFF,DEC,RA,all_ON;track=OFF,Moon,Sun,Star;speed=Guide,Center,Find,Max]';
    'get_unkown_x46r',              'X46r',       '%s','query X46r, e.g. "c1"';
    'set_altaz',                    'AA',         '',     'set to alt/az mode';
    'set_autoguiding_speed_dec',    'X21%02d',    '',     'set auto guiding speed on DEC (xx for 0.xx %)';
    'set_autoguiding_speed_ra',     'X20%02d',    '',     'set auto guiding speed on RA (xx for 0.xx %)';
    'set_date',                     'SC %02d%02d%02d','','set local date(mm,dd,yy)(0)';
    'set_dec',                      'Sd %+03d*%02d:%02d', '','set DEC(dd,mm,ss)';
    'set_equatorial',               'AP',         '','set mount to equatorial mode';
    'set_guiding_speed_dec',        'X21%2d',     '','set DEC speed(dd percent)';
    'set_guiding_speed_ra',         'X20%2d',     '','set RA speed(dd percent)';
    'set_highprec',                 'U',          '','switch to high precision';
    'set_hemisphere_north',         'TTHS0',      '','set North hemisphere';
    'set_hemisphere_south',         'TTHS1',      '','set South hemisphere';
    'set_home_pos',                 'X31%02d%02d%02d','','sync home position';
    'set_keypad_off',               'TTSFr',      '','disable keypad';
    'set_keypad_on',                'TTRFr',      '','enable keypad';
    'set_meridianflip_forced_off',  'TTRFd',      '','disable meridian flip forced';  
    'set_meridianflip_forced_on',   'TTSFd',      '','enable meridian flip forced';     
    'set_meridianflip_off',         'TTRFs',      '','disable meridian flip';     
    'set_meridianflip_on' ,         'TTSFs',      '','enable meridian flip';    
    'set_mount_gear_ratio',         'TTSM%1d',    '','set mount model (x=1-8 for M0,576,Linear,720,645,1440,Omega,B230)'; 
    'set_park_pos',                 'X352',       '','sync park position (0)';
    'set_polar_led',                'X07%1d',     '','set the polar LED level in 10% (x=0-9)';
    'set_pulse_east',               'Mge%04d',    '','move east for (t msec)';
    'set_pulse_north',              'Mgn%04d',    '','move north for (t msec)';
    'set_pulse_south',              'Mgs%04d',    '','move south for (t msec)';
    'set_pulse_west',               'Mgw%04d',    '','move west for (t msec)';
    'set_ra',                       'Sr %02d:%02d:%02d', '','set RA(hh,mm,ss)';
    'set_reverse_ra',               'X1A10',      '','set RA reverse direction';
    'set_reverse_dec',              'X1A01',      '','set DEC reverse direction';
    'set_reverse_off',              'X1A00',      '','set normal RA/DEC direction';
    'set_sidereal_time',            'X32%02d%02d%02d','','set local sidereal time(hh,mm,ss)';
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
    'set_UTCoffset',                'SG %+03d',   '','set UTC offset(hh)';
    'abort',                        'Q',          '','abort current move'; 
    'full_abort',                   'FQ',         '','full abort/stop (switch off)';
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
    'get_localdate',                'GC',         '%d%c%d%c%d', 'invalid:query Local date(mm,dd,yy)';
    'get_locattime',                'GL',         '%2d:%2d:%2d','invalid:query local time(hh,mm,ss)';
    'get_tracking_freq',            'GT',         '%f','invalid:query tracking frequency';
    'get_UTCoffset',                'GG',         '%f','invalid:query UTC offset';
  };
  c = [];
  for index=1:size(commands,1)
    this = commands(index,:);
    f.name   = this{1};
    f.send   = [ ':' this{2} '#' ];
    f.recv   = this{3};
    f.comment= this{4};
    c = [ c f ];
  end
  
end

function available = getports
  % GETPORTS find available serial ports.
  
  % we use the error code returned by Matlab
  ME = [];
  try
    s = serial('IMPOSSIBLE_PORT'); fopen(s);
  catch ME
    % nop
  end
  
  l = getReport(ME);
  available = findstr(l, 'Available ports');
  if ~isempty(available)
    l = textscan(l(available(1):end),'%s','Delimiter','\n\r');
    available = l{1};
  end
  if iscell(available) available = available{1}; end
  if isempty(available) 
    available = 'ERROR: No available serial port. Check connection/reconnect.'; 
  end
end % getports

function str = flush(self)
  % FLUSH read the return values from device
  if ~isvalid(self.serial), disp('flush: Invalid serial port'); return; end
  com = self.serial;
  str = '';
  while com.BytesAvailable
    str = [ str fscanf(com) ];
  end
end % flush

function [LST, JD, GST] = getLocalSiderealTime(longitude, t0)
  % getLocalSiderealTime compute LST
  %   getLocalSiderealTime(longitude, [year month day hour minute seconds]) uses
  %   specified date and time.
  %
  %   getLocalSiderealTime(longitude) uses current date and time (but does not 
  %   correct for UTC offset).
  if nargin < 1
    longitude = 2;
  end
  if nargin <= 1
    t0 = clock;
  end
  fprintf('Date                               %s\n', datestr(t0));
  year=t0(1); month=t0(2);  day=t0(3); 
  hour=t0(4);   min=t0(5);  sec=t0(6); 
  UT = hour + min/60 + sec/3600;
  J0 = 367*year - floor(7/4*(year + floor((month+9)/12))) ...
      + floor(275*month/9) + day + 1721013.5;
  JD = J0 + UT/24;              % Julian Day
  fprintf('Julian day                         %6.4f [days]\n',JD);
  JC = (J0 - 2451545.0)/36525;
  GST0 = 100.4606184 + 36000.77004*JC + 0.000387933*JC^2 - 2.583e-8*JC^3; %[deg]
  GST0 = mod(GST0, 360);  % GST0 range [0..360]
  fprintf('Greenwich sidereal time at 0 hr UT %6.4f [deg]\n',GST0);
  GST = GST0 + 360.98564724*UT/24;
  GST = mod(GST, 360);  % GST range [0..360]
  fprintf('Greenwich sidereal time at UT[h]   %6.4f [deg]\n',GST);
  LST = GST + longitude;
  LST = mod(LST, 360);  % LST range [0..360]
  fprintf('Local sidereal time                %6.4f [deg]\n',LST);
  [h,m,s] = angle2hms(LST);
  fprintf('                                   %2d:%2d:%2d\n',h,m,s);
end % getLocalSiderealTime

function place = getplace
  % could also use: https://api.ipdata.co/
  % is network service available ?
  ip = java.net.InetAddress.getByName('ip-api.com');
  if ip.isReachable(1000)
    ip = urlread('http://ip-api.com/json');
    ip = parse_json(ip);  % into struct (private)
    place = [ ip.lon ip.lat ];
    disp([ mfilename ': You seem to be located near ' ip.city ' ' ip.country ' [long lat]=' mat2str(place) ' obtained from http://ip-api.com/json' ]);
  else
    place = [];
  end
end % end

function [h,m,s] = angle2hms(ang,in)
  % angle2hms convert angle from [deg] to hh:mm:ss
  if nargin < 2, in='hours'; end
  if strcmp(in, 'hours')
    ang = ang/15;
  end
  h=fix(ang); m=fix((ang-h)*60); s=(ang-h-m/60)*3600;
end % angle2hms

function ang = hms2angle(h,m,s)
  % hms2angle convert hh:mm:ss to an angle in [deg]
  if nargin == 1 && numel(h) == 3
    m = h(2); s=h(3); h=h(1);
  end
  ang = double(h) + double(m)/60 + double(s)/3600;
end % hms2angle

function str = repradec(str)
  %repradec: replace string stuff and get it into num
  str = lower(str);
  for rep = {'h','m','s',':','°','deg','d','''','"','*','[',']'}
    str = strrep(str, rep{1}, ' ');
  end
  str = str2num(str);
end

function [h,m,s] = convert2hms(in,hours)
  h=[]; m=[]; s=[];
  if nargin < 2, hours='hours'; end
  if isempty(in), return; end
  if ischar(in) % from HH:MM:SS
    str = repradec(in);
    if isnumeric(str) && all(isfinite(str))
      in = str;
    end
  end
  if isnumeric(in) 
    if isscalar(in)
      [h,m,s] = angle2hms(in,hours);
    elseif numel(in) == 3
      h=in(1); m=in(2); s=in(3);
    end
  end
end % convert2hms

function c = gotora(self, ra)
  [h1,m1,s1] = convert2hms(ra,'hours'); c = '';
  if ~isempty(h1)
    c = write(self, 'set_ra',  h1,m1,round(s1));
    self.target_ra = [h1 m1 s1];
    pause(0.25); % make sure commands are received
    % now we request execution of move: get_slew ":MS#"
    write(self, 'get_slew');
  elseif isempty(self.target_ra), self.target_ra=self.state.get_ra;
  end
end % gotora

function c = gotodec(self, dec)
  [h2,m2,s2] = convert2hms(dec,'deg'); c = '';
  if ~isempty(h2)
    c = write(self, 'set_dec', h2,m2,round(s2));
    self.target_dec = [h2 m2 s2];
    pause(0.25); % make sure commands are received
    % now we request execution of move: get_slew ":MS#"
    write(self, 'get_slew');
    pause(0.25); % make sure commands are received
  elseif isempty(self.target_dec), self.target_dec=self.state.get_dec;
  end
end % gotodec
