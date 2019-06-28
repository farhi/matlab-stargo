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
  %   sg = stargo('/dev/ttyUSB0');
  %   sg = stargo('COM1');
  %
  % When using a Bluetooth connection, we recommend to use BlueMan.
  % Install it with e.g. 'sudo apt install blueman' or 'yum install blueman'.
  % Then assign a serial port to the connection (e.g. /dev/rfcomm0) and use:
  %   sg = stargo('/dev/rfcomm0');
  %
  % (c) E. Farhi, GPL2 - version 19.06
  
  % list of commands to be used with StarGo, derived from LX200 protocol.
  properties
    dev       = 'COM1'; 
    version   = '';
    place     = {};       % GPS location and hour shift/UTC
    UserData  = [];
    serial    = [];       % the serial object
    state     = [];       % detailed controller state (raw)
    
  end % properties
  
  properties(Access=private)
    timer     = [];       % the current Timer object which sends a getstate regularly
    
    start_time= datestr(now);

  end % properties
  
  properties (Constant=true)
    catalogs     = getcatalogs;       % load catalogs at start
    % commands: field, input_cmd, output_fmt, description
    commands     = getcommands;
  end % shared properties        
                
  events            
    gotoReached     
    updated   
  end              
  
  methods
  
    function sb = stargo(dev)
      % STARGO start communication an given IP and initialize the stargo
      %   sb=STARGO(dev) specify a device, e.g. 169.254.1.1 192.168.1.19 ...
      
      if nargin
        sb.dev = dev;
      end
      sb.start_time = now;
      
      % connect serial port
      try
        sb.serial = serial(sb.dev); fopen(sb.serial);
      catch ME
        disp([ mfilename ': failed to connect ' sb.dev ]);
        disp(getports);
        return
      end
      sb.serial.Terminator = '#';
      identify(sb);
      disp([ '[' datestr(now) '] ' sb.version ' connected to ' sb.dev ]);
      start(sb);
      
    end % stargo
    
    function val = queue(self, cmd, nowait_flag)
      % queue: sends the input, waits for completion, get result as a string
      if nargin == 1, val = flush(self); return; end
      if nargin < 3, nowait_flag = false;
      elseif ischar(nowait_flag)
        if any(strcmp(nowait_flag,{'nowait','async','background'}))
          nowait_flag = false;
        else nowait_flag = true; end
      end
      
      % we 
      if iscellstr(cmd), cmd = sprintf('%s', cmd{:}); end
      val = [];
      fprintf(self.serial, cmd);
      
 
      % flush and get results back
      if ~nowait_flag
        % we wait for output to be available (we know there will be something)
        t0 = clock;
        while etime(clock, t0) < 2 && self.serial.BytesAvailable==0
          pause(0.1)
        end
        % we wait until there is nothing else to retrieve
        t0 = clock;
        while etime(clock, t0) < 2 && self.serial.BytesAvailable
          val = [ val flush(self) ];
          pause(0.1)
        end
        
      else
        val = flush(self);
      end
      
      if strfind(val, ':Z1')
        % parse motion state ':Z1%01d%01d%01d' -> [m,t,s]
        % m = 0 both motors are OFF (no power)
        % m = 1 RA motor OFF DEC motor ON
        % m = 2 RA motor ON DEC motor OFF
        % m = 3 both motors are ON
        % Tracking modes
        % t = 0 no tracking at all
        % t = 1 tracking at moon speed
        % t = 2 tracking at sun speed
        % t = 3 tracking at stars speed (sidereal speed)
        % Slew speed index
        % s = 0 GUIDE speed
        % s = 1 CENTERING speed
        % s = 2 FINDING speed
        % s = 3 MAX speed
      end

    end % queue
    
    function delete(self)
      % close connection
      flush(self);
      fclose(self.serial)
    end
    
    function v = identify(self)
      v = queue(self, [ ':GVP#', ':GVN#', ':GVD#' ]);
      v = strrep(v, '#', ' ');
      self.version = v;
    end % identify
    
    function [status,fields,cmd] = getstatus(self, flag)
      % GETSTATUS get the mount status (RA, DEC, Status)
      
      if nargin < 2, flag = 'short'; end
      
      % :X590#    getEqCoordinates        "RD%08lf%08lf"  RA in 1e6  DEC in 1e5
      cmds = {};
      
      if any(strcmp(flag,{'long','full'}))
        % :Gt#      getSiteLatitude         "%f" -> double
        % :Gg#      getSiteLongitude        "%f" -> double
        % :TTGFh#   get ST4 port status     0=vh0 1=vh1
        % :GW#      get scope alignment status  <mount><tracking><align>, e.g. AT0
        % :TTGFr#   get Keypad status       0=vr0 1=vr1
        % :TTGFs#   get meridian flip status 0=vs0 1=vs1
        % :X34#     get MotorStatus x y     m%d%d
        % :X38#     get park/home status    p%d
        % :TTGMX#   get system slew speed   %da%d
        % :X22#     get guiding speed       %db%d
        % :X39#     get side of pier        P%c
        cmds = { ...
          'site_latitude',    
'site_longitude',    
'status_st4',      
'status_alignment',    
'status_keypad',    
'status_meridian',    
'status_meridian_forced',  
'status_park',      
'speed_slew',      
'speed_guiding',    
'status_invert',    
'status_highprec',    
'status_slew',      
'status_locattime',    
'status_locatdate',    
'status_track_freq',    
'status_UTFoffset',    
'status_radec',     
'status_motors',    
        };
      end
      cmds{end+1}   = 'X590'; % RA DEC
      cmds{end+1}   = 'status_radec';
      cmds{end+1}   = 'RD%d+%d';
      
      cmds{end+1}   = 'X34';  % Motors status
      cmds{end+1}   = 'status_motor';
      cmds{end+1}   = 'm%d%d';
      
      cmd    = cmds(1:3:(end-2));
      fields = cmds(2:3:(end-1));
      
      cmd = strcat(':', cmd, '#');
      % send all status requests
      status = queue(self, cmd);
      
      status = textscan(status,'%s','Delimiter','#');
      status = status{1};
      if isempty(status{end}) && numel(status) == numel(cmd)+1
        status(end) = [];
      end
      
      % now interpret state values
      fmt = cmds(3:3:end);

      % build a struct
      if numel(status) == numel(fields)
        state = cell2struct(status', fields, 2);
        values = cell(size(fields));
        for index=1:numel(fields)
          % values(index) = sscanf(status{index}, fmt{index});
        end
      else state = status; values=[];
      end
      self.state = state;

    end % getstatus
    
    function gotoradec(self, ra, dec)
      % GOTARADEC send the mount to given RA,DEC coordinates or named object.
    end % gotoradec
    
    function stop(self)
      % STOP stop any mount move.
    end % stop
    
    function start(self)
      % START reset/initialise/check the mount
      getstatus(self, 'full');
    end %start
    
    function ret=home(self)
      % HOME send the mount to its home position (e.g. pointing polar in EQ).
      ret = queue(self, 'X361');
      if ~strcmp(ret, 'pA')
        disp([ mfilename ': WARNING: Failed to send mount to HOME position with answer ' ret ]);
      end
    end % home
    
    function ret=park(self, option)
      % PARK send the mount to a reference parking position.
      
      if nargin < 2, option = 'send'; end
      ret = []; 
      switch option
      case {'send','goto','park'}
        ret = queue(self, 'X362');
        if ~strcmp(ret, 'pB')
          disp([ mfilename ': WARNING: Failed to send mount to PARK position with answer ' ret ]);
        end
      case {'set'}
        ret = queue(self, 'X352');
        if ~strcmp(ret, '0')
          disp([ mfilename ': WARNING: Failed to set PARK position with answer ' ret ]);
        end
      otherwise
        disp([ mfilename ': WARNING: unknown PARK option. Should be "goto" (default) or "set".' ]);
        return
      end
      
    end % park
    
    function unpark(self)
      % UNPARK wake up the mount from parking.
      ret = queue(self, 'X370');
      if ~strcmp(ret, 'p0')
        disp([ mfilename ': WARNING: Failed to reset mount from PARK position with answer ' ret ]);
      end
    end % unpark
    
    function align(self)
      sync(self);
    end % align
    
    function sync(self)
    end % sync
    
    function zoom(self, index)
      % ZOOM set slew speed. Level should be 0,1,2 or 3.
      if nargin <2, return; end
      switch (index)
      case 0
          cmd='TTMX0606';
      case 1
          cmd='TTMX0808';
      case 2
          cmd='TTMX0909';
      case 3
          cmd='TTMX1212';
      otherwise
          disp([ mfilename ': WARNING: Unexpected system slew speed mode ' num2str(index));
          return
      queue(self, cmd);
    end % zoom
    
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
        disp([ mfilename ': Found object ' name ' as: ' found.NAME ])
        if found.DIST > 0
          disp(sprintf('  %s: Magnitude: %.1f ; Type: %s ; Dist: %.3g [ly]';
            found.catalog, found.MAG, found.TYPE, found.DIST*3.262 ));
        else
          disp(sprintf('  %s: Magnitude: %.1f ; Type: %s';
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

function decode_status(self, state)
end

function c = getcommands
  commands = { ...                   
    'abort',                        'Q',          '',         'abort current move'; 
    'get_alignment',                'GW',         '%c%c%01d', 'query Scope alignment status(mt,tracking,nb_alignments)';
    'get_firmwaredate',             'GVD',        '','query firmware date'; 
    'get_firmware',                 'GVN',        '%f','query firmware version';
    'get_highprec',                 'GR',         '','query RA precision format(nb digits)'; 
    'get_keypad',                   'TTGFr',      'vr%01d','query Keypad status(0,1)';     
    'get_locatdate',                'GC',         '%d%*c%d%*c%d','invalid:query Local date(mm,dd,yy)';
    'get_locattime',                'GL',         '%02d:%02d:%02d','invalid:query local time(hh,mm,ss)';
    'get_manufacturer',             'GVP',        '','manufacturer';
    'get_meridian_forced',          'TTGFd',      'vd%01d','query meridian flip forced(TF)';
    'get_meridian',                 'TTGFs',      'vs%d','query meridian flip forced(TF)';  
    'get_motors',                   'X34',        'm%01d%01d','query motors state(0:5==stop,tracking,accel,decel,lowspeed,highspeed)'; 
    'get_park',                     'X38',        'p%s','query tracking state(0=unparked,1=homed,2=parked,A=slewing,B=slewing2park)';   
    'get_radec',                    'X590',       'RD%08lf%08lf','query RADEC(RA*1e6,DEC*1e5) in deg';
    'get_sideofpier',               'X39',        'P%c','query pier side(X=unkown,E=east2east,W=east2west)';  
    'get_site_latitude',            'Gt',         '%dt%d:%d','query Site Latitude';  
    'get_site_longitude',           'Gg',         '%dg%d:%d','query Site Longitude';     
    'get_slew',                     'MS',         '%i','query slewing state(0=slewing)';     
    'get_speed_guiding',            'X22',        '%02db%2d','query guiding speeds(ra,dec)';   
    'get_speed_slew',               'TTGMX',      '%02da%02d','query slewing speed(xx=6,8,9,12,yy)';    
    'get_st4',                      'TTGFh',      'vh%01d','query ST4 status(TF)';  
    'get_tracking_freq',            'GT',         '%f','invalid:query tracking frequency';
    'get_UTFoffset',                'GG',         '%f','invalid:query UTC offset';
    'home',                         'X361',       'pA','send mount to home';
    'park',                         'X362',       'pB','send mount to park';
    'set_date',                     'SC %02d%02d%02d','0','set local date(mm,dd,yy)';
    'set_dec',                      'Sd%+03d*%02d:%02d', '','set DEC(dd,mm,ss)';
    'set_guiding_speed_dec',        'X21%2d',     '','set DEC speed(dd percent)';
    'set_guiding_speed_ra',         'X20%2d',     '','set RA speed(dd percent)';
    'set_highprec',                 'U',          '','switch to high precision';
    'set_home_pos',                 'X31%s',      '','sync home position';
    'set_keypad_off',               'TTSFr',      '','disable keypad';
    'set_keypad_on',                'TTRFr',      '','enable keypad';
    'set_meridianflip_forced_off',  'TTRFd',      '','disable meridian flip forced';  
    'set_meridianflip_forced_on',   'TTSFd',      '','enable meridian flip forced';     
    'set_meridianflip_off',         'TTRFs',      '','disable meridian flip';     
    'set_meridianflip_on' ,         'TTSFs',      '','enable meridian flip';     
    'set_park_pos',                 'X352',       '0','sync park position';
    'set_pulse_east',               'Mge%04u',    '','move east for (t msec)';
    'set_pulse_north',              'Mgn%04u',    '','move north for (t msec)';
    'set_pulse_south',              'Mgs%04u',    '','move south for (t msec)';
    'set_pulse_west',               'Mgw%04u',    '','move west for (t msec)';
    'set_ra',                       'Sr%02d:%02d:%02d', '','set RA(hh,mm,ss)';
    'set_sidereal_time',            'X32%02hd%02hd%02hd','','set local sideral time(hexa hh,mm,ss)';
    'set_site_latitude',            'St%+03d*%02d:%02d', '','set site latitude(dd,mm,ss)'; 
    'set_site_longitude',           'Sg%+04d*%02u:%02u', '','set site longitude(dd,mm,ss)'; 
    'set_speed_center',             'RC',         '','set slew speed center (2/4)';     
    'set_speed_find',               'RM',         '','set slew speed find (3/4)';     
    'set_speed_guide',              'RG',         '','set slew speed guide (1/4)';     
    'set_speed_max',                'RS',         '','set slew speed max (4/4)';     
    'set_st4_off',                  'TTRFh',      '','disable ST4 port';
    'set_st4_on',                   'TTSFh',      '','enable ST4 port';
    'set_system_speed_fastest',     'TTMX1212',   '','set system slew speed max (4/4)';     
    'set_system_speed_fast',        'TTMX0909',   '','set system slew speed fast (3/4)';     
    'set_system_speed_low',         'TTMX0606',   '','set system slew speed low (1/4)';     
    'set_system_speed_medium',      'TTMX0808',   '','set system slew speed medium (2/4)';     
    'set_time',                     'SL %02d:%02d:%02d', '0','set local time(hh,mm,ss)';
    'set_tracking_lunar',           'TL',         '','set tracking lunar';
    'set_tracking_none',            'TM',         '','set tracking none';
    'set_tracking_off',             'X120',       '','enable tracking';     
    'set_tracking_on',              'X122',       '','disable tracking';     
    'set_tracking_rate',            'X1E%04d',    '','set tracking rate';
    'set_tracking_sidereal',        'TQ',         '','set tracking sidereal';
    'set_tracking_solar',           'TS',         '','set tracking solar';
    'set_UTFoffset',                'SG %+03d',   '','set UTF offset(hh)';
    'start_slew_east',              'Me',         '','start to move east';
    'start_slew_north'              'Mn',         '','start to move north';     
    'start_slew_south'              'Ms',         '','start to move south';   
    'start_slew_west',              'Mw',         '','start to move west';
    'stop_slew_east',               'Qe',         '','stop to move east';
    'stop_slew_north',              'Qn',         '','stop to move north';
    'stop_slew_south',              'Qs',         '','stop to move south';
    'stop_slew_west',               'Qw',         '','stop to move west';
    'sync',                         'CM',         '','sync (align), i.e. indicate we are on last target';
    'unpark',                       'X370',       'p0','wake up from park';  
    };
  % we build a struct which has command description as fields
  c = [];
  for index=1:size(commands,1)
    this = commands(index,:);
    c.(commands{index,1}).input  = this{2};
    c.(commands{index,1}).output = this{3};
    c.(commands{index,1}).comment= this{4};
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
  com = self.serial;
  str = '';
  while com.BytesAvailable
    str = [ str fscanf(com) ];
  end
end % flush
