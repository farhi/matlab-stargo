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
    place     = {};       % GPS location and hour shift/UTC
    UserData  = [];
    serial    = [];       % the serial object
    state     = [];       % detailed controller state (raw)
    bufferSent = [];
    bufferRecv = '';
    
  end % properties
  
  properties(Access=private)
    timer     = [];       % the current Timer object which sends a getstatus regularly
    
    start_time= datestr(now);

  end % properties
  
  properties (Constant=true)
    catalogs       = getcatalogs;       % load catalogs at start
    % commands: field, input_cmd, output_fmt, description
    commands       = getcommands;
  end % shared properties        
                
  events            
    gotoReached     
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
      identify(sb);
      disp([ '[' datestr(now) '] ' sb.version ' connected to ' sb.dev ]);
      % start(sb);
      
    end % stargo
    
    % I/O stuff ----------------------------------------------------------------
    
    function write(self, cmd, varargin)
      % WRITE sends a single command, does not wait for answer.
      %   WRITE(self, cmd) sends a single command asynchronously.
      %   The command can be a single serial string, or the command name,
      %   or a structure with 'send' field.
      %
      %   WRITE(self, { cmd1, cmd2 ... }) same as above with multiple commands.
      %
      %   WRITE(self, cmd, arg1, arg2, ...) same as above when a single command 
      %   requires additional arguments.
      
      cmd = strcmp(self, cmd);  % identify command, as a struct array
      % send commands one by one
      for index=1:numel(cmd)
        argin = numel(find(cmd(index).send == '%'));
        if argin ~= numel(varargin)
          disp([ '[' datestr(now) '] WARNING: write: command ' cmd(index).send ...
            ' requires ' str2num(argin) ' arguments but only ' ...
            num2str(numel(varargin)) ' are given.' ]);
        else
          fprintf(self.serial, cmd(index).send, varargin{:}); % SEND
          % register expected output for interpretation.
          if ~isempty(cmd(index).recv) && ischar(cmd(index).recv)
            self.bufferSent = [ self.bufferSent cmd(index) ]; 
          end
        end
      end
    end % write
    
    function val = read(self)
      % READ receives the output from the serial port.
      
      % this can be rather slow as there are pause calls.
      % registering output may help.
      
      % flush and get results back
      val = '';
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
      % store output
      self.bufferRecv = strtrim([ self.bufferRecv val ]);
      % interpret results
      parseparams(self);
      val = strrep(val, '#',' ');
    end % read
    
    function out = strcmp(self, in)
      % STRCMP identify commands within available ones.
      %   STRCMP(self, CMD) searches for CMD in available commands. CMD can be
      %   given as a single serial command. The return value is a structure.
      %
      %   STRCMP(self, { 'CMD1' 'CMD2' ... }) does the same with an array as input.
      if isstruct(in) && isfield(in,'send'), out = in; return;
      elseif isnumeric(in), out = self.commands(in); return;
      elseif ~ischar(in) && ~iscellstr(in)
        error([ '[' datestr(now) '] WARNING: strcmp: invalid input type ' class(in) ]);
      end
      in = cellstr(in);
      out = [];
      for index = 1:numel(in)
        this_in = in{index};
        if this_in(1) == ':', list = { self.commands.send };
        else                  list = { self.commands.name }; end
        tok = find(strcmp(list, this_in));
        if numel(tok) == 1
          out = [ out self.commands(tok) ];
        else
          disp([ '[' datestr(now) '] WARNING: strcmp: can not find command ' this_in ' in list of available ones.' ]);
          out.name = 'custom command';
          out.send = this_in;
          out.recv = '';
          out.comment = '';
        end
      end
      
    end % strcmp
    
    function delete(self)
      % DELETE close connection
      fclose(self.serial)
    end

    function p = parseparams(self)
      % PARSEPARAMS interpret output and decode it.
      recv = self.bufferRecv; p=[];
      if isempty(recv), return; end
      % cut output from serial port into separate tokens
      recv = textscan(recv,'%s','Delimiter','# ','MultipleDelimsAsOne',true);
      recv = recv{1};
      if isempty(recv), return; end
      allSent = self.bufferSent; toremove = [];
      % we search for a pattern in sent that matches the actual recieved string
      for indexR=1:numel(recv)
        if isempty(recv{indexR}), continue; end
        for indexS=1:numel(allSent)
          sent = allSent(indexS); tok = [];
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
            self.state.(sent.name) = tok;
            p.(sent.name)   = tok;
            toremove(end+1) = indexS; % clear this request for search
            recv{indexR}    = [];     % clear this received output as it was found
            break; % go to next received item
          end % if tok
        end % for indexS
      end % for indexR
      self.bufferSent(toremove) = [];
      if ~all(cellfun(@isempty, recv))
        self.bufferRecv = sprintf('%s#', recv{:});
      else
        self.bufferRecv = '';
      end
    end % parseparams
    
    % commands -----------------------------------------------------------------
    
    function v = identify(self)
      % IDENTIFY reads the StarGo identification string.
      write(self, {'get_manufacturer','get_firmware','get_firmwaredate'});
      self.version = read(self);
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
          'get_speed_slew', 'get_speed_guiding', 'get_sideofpier','get_ra','get_dec', ...
          'get_meridian_forced', 'get_slew'};
        % invalid: get_localdate get_locattime get_UTFoffset get_tracking_freq
      otherwise % {'short','fast'}
        list = {'get_radec','get_motors','get_ra','get_dec'};
      end
      write(self, list);
      val = read(self);
    end % getstatus

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
    'get_radec',                    'X590',       'RD%8d%8d','query RADEC(RA*1e6,DEC*1e5) in deg';
    'get_sideofpier',               'X39',        'P%c','query pier side(X=unkown,E=east2east,W=east2west)';  
    'get_site_latitude',            'Gt',         '%dt%d:%d','query Site Latitude';  
    'get_site_longitude',           'Gg',         '%dg%d:%d','query Site Longitude';     
    'get_slew',                     'MS',         '%d','query slewing state(0=slewing)';     
    'get_speed_guiding',            'X22',        '%db%d','query guiding speeds(ra,dec)';   
    'get_speed_slew',               'TTGMX',      '%da%d','query slewing speed(xx=6,8,9,12,yy)';    
    'get_st4',                      'TTGFh',      'vh%1d','query ST4 status(TF)';  
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
    'home',                         'X361',       'pA','send mount to home';
    'park',                         'X362',       'pB','send mount to park';
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
    'get_localdate',                'GC',         '%d%c%d%c%d', 'invalid:query Local date(mm,dd,yy)';
    'get_locattime',                'GL',         '%2d:%2d:%2d','invalid:query local time(hh,mm,ss)';
    'get_tracking_freq',            'GT',         '%f','invalid:query tracking frequency';
    'get_UTFoffset',                'GG',         '%f','invalid:query UTC offset';
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
  com = self.serial;
  str = '';
  while com.BytesAvailable
    str = [ str fscanf(com) ];
  end
end % flush

