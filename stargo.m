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
  % :X590#    getEqCoordinates        "RD%08lf%08lf"  RA in 1e6  DEC in 1e5
  % :Gt#      getSiteLatitude         "%f" -> double
  % :Gg#      getSiteLongitude        "%f" -> double
  % :TTGFh#   get ST4 port status
  % :GW#      get scope alignment status
  % :TTGFr#   get Keypad status
  % :TTGFs#   get meridian flip status
  % :GL#      get local time
  % :GG#      get UTF offset
  % :GT#      get track frequency
  % :X34#     getMotorStatus x y
  % :X38#     get park/home status
  % :TTGMX#   get system slew speed
  % :X22#     get guiding speed
  % :X39#     get side of pier
  % :GR#      get RA (lx200)
  % :GR#      get DEC (lx200)
  
  % :Q#       ABORT
  % :CM#      synchronise
  % :X361#    setMountGotoHome        "pA" == OK
  % :X362#    Park                    "pB" == OK
  % :X370#    unPark                  "p0" == OK
  % :X352#    set park position (e.g. after home)

  properties
    dev       = 'COM1'; 
    version   = '';
    place     = {};       % GPS location and hour shift/UTC
    UserData  = [];
    serial    = [];       % the serial object
    
  end % properties
  
  properties(Access=private)
    timer     = [];       % the current Timer object which sends a getstate regularly
    
    start_time= datestr(now);

  end % properties
  
  properties (Constant=true)
    catalogs     = getcatalogs;       % load catalogs
  end % shared properties
  
  events
    gotoReached
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
        l = getReport(ME);
        available = findstr(l, 'Available ports');
        if ~isempty(available)
          l = textscan(l(available(1):end),'%s','Delimiter','\n\r');
          available = l{1};
        end
        disp([ mfilename ': Invalid serial/bluetooth port ' sb.dev ]);
        if iscell(available) available = available{1}; end
        disp(available)
        return
      end
      sb.serial.Terminator = '#';
      
    end % stargo
    
    function val = queue(self, cmd, nowait_flag)
      % queue: sends the input, waits for completion, get result as a string
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

    end % queue
    
    function str = flush(self)
      com = self.serial;
      str = '';
      while com.BytesAvailable
        str = [ str fscanf(com) ];
      end
    end % flush
    
    function delete(self)
      % close connection
      flush(self);
      fclose(self.serial)
    end
    
    function v = identify(self)
      v = mfilename;
      v = [ v queue(self, { ':GVP#', ':GVN#', ':GVD#' },'sync') ];
      self.version = v;
    end % identify
    
    function [status,fields,cmd] = getstatus(self, flag)
      % get RA, DEC, Status, mount date
      
      if nargin < 2, flag = 'short'; end
      
      % :X590#    getEqCoordinates        "RD%08lf%08lf"  RA in 1e6  DEC in 1e5
      cmd = {}; fields = {};
      
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
        cmd = {'Gt','Gg','TTGFh','GW','TTGFr','TTGFs','X34', ...
          'X38','TTGMX','X22','X39'};
        
        fields = {'site_latitude','site_longitude','status_st4', ...
          'status_alignment','status_keypad','status_meridian', ...
          'status_motor','status_park', ...
          'speed_slew', 'speed_guiding','status_invert'};
        
        % status = cell2struct(values,fields,2);
      end
      cmd{end+1}    = 'X590';
      fields{end+1} = 'status_radec';
      
      cmd = strcat(':', cmd, '#');
      status = queue(self, cmd);
      status = textscan(status,'%s','Delimiter','#');
      status = status{1};
      if isempty(status{end}) && numel(status) == numel(cmd)+1
        status(end) = [];
      end
      if numel(status) == numel(fields)
        status = cell2struct(status', fields, 2);
      end
      
    end % getstatus
    
    function gotoradec(self, ra, dec)
    end % gotoradec
    
    function stop(self)
    end % stop
    
    function start(self)
      % :TTGFh#   get ST4 port status
      % :GW#      get scope alignment status
      % :TTGFr#   get Keypad status
      % guiding speed
      % meridian flip status
      % aux port status
      % :X34#     getMotorStatus x y
      % :X38#     park/home status
      % :TTGMX#   get system slew speed
    end %start
    
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

function catalogs = getcatalogs
  % getcatalogs: load catalogs for stars and DSO.

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


