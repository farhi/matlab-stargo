function config = settings_apply(self, fig, config0)
  % SETTINGS_APPLY apply settings from dialogue
  
  try
    config = get(fig, 'UserData');
  catch
    config = [];
  end
  if isempty(config0) || ~isstruct(config0) || ~isstruct(config), return; end
  % check for changes
  for f=fieldnames(config)'
    val  = config.(f{1});
    val0 = config0.(f{1});
    remove_me = false;
    % remove type changed members
    if ~strcmp(class(val),class(val0)), remove_me=true; 
    % remove unset members
    elseif isempty(val) || strcmp(val, 'unset'), remove_me=true; 
    % remove unchanged members
    elseif ischar(val) && ischar(val0) && strcmp(val, val0), remove_me=true;
    elseif isequal(val, val0), remove_me=true; end
    if remove_me
      config = rmfield(config, f{1});
    end
  end
  disp 'applying changes:'
  disp(config)
  % apply changes
  for f=fieldnames(config)'
    val = config.(f{1});
    switch f{1}
    case 'tracking'
      tracking(self, strtok(config.tracking));
    case 'polar_led'
      config.polar_led = strtok(config.polar_led);
      write(self, 'set_polar_led', str2double(config.polar_led(1)));
    case 'meridianflip'
      meridianflip(self, strtok(config.meridianflip));
    case 'st4'
      if config.st4, write(self, 'set_st4_on');
      else           write(self, 'set_st4_off'); end
    case 'keypad'
      if config.keypad, write(self, 'set_keypad_on');
      else           write(self, 'set_keypad_off'); end
    case 'mode'
      write(self, [ 'set_' lower(config.mode) ]);
    case 'hemisphere'
      write(self, [ 'set_hemisphere_' lower(config.hemisphere) ]);
    case 'mount_gear_ratio'
      config.mount_gear_ratio = strtok(config.mount_gear_ratio);
      write(self, 'set_mount_gear_ratio', config.mount_gear_ratio(1));
    case 'motor_torque'
      config.motor_torque = str2double(strtok(config.motor_torque));
      write(self, 'set_torque', config.motor_torque);
    case 'autoguiding_speed'
      config.autoguiding_speed  = str2num(config.autoguiding_speed);
      if numel(config.autoguiding_speed) == 2
        write(self, 'set_autoguiding_speed_ra', config.autoguiding_speed(1));
        write(self, 'set_autoguiding_speed_dec', config.autoguiding_speed(2));
      end
    case 'reverse_radec'
      switch strtok(config.reverse_radec)
      case 'normal'
        config.reverse_radec = [ 0 0 ];
      case 'RA'
        config.reverse_radec = [ 1 0 ];
      case 'DEC'
        config.reverse_radec = [ 0 1 ];
      case 'RA/DEC'
        config.reverse_radec = [ 1 1 ];
      end
      write(self, 'set_reverse_radec', config.reverse_radec);
    case 'system_speed_center'
      write(self, [ 'set_system_speed_center_' strtok(config.system_speed_center) ]);
    case 'system_speed_guide'
      write(self, [ 'set_system_speed_guide_' strtok(config.system_speed_guide) ]);
    case 'system_speed_slew'
      config.system_speed_slew  = str2num(config.system_speed_slew);
      if numel(config.system_speed_slew) == 2
        write(self, [ 'set_system_speed_slew_' config.system_speed_slew ]);
      end
    case 'longitude'
      config.longitude          = repradec(config.longitude);
      if numel(config.longitude) == 1
        [d,m,s] = angle2hms(config.longitude);
        config.longitude = [ d m s ];
      end
      if numel(config.longitude) == 3
        queue(self, 'set_site_longitude', round(config.longitude));
        pause(0.1)
        if isobject(self.private.skychart)
          sc = self.private.skychart;
          sc.place(1) = hms2angle(config.longitude);
        end
      end
    case 'latitude'
      config.latitude           = repradec(config.latitude);
      if numel(config.latitude) == 1
        [d,m,s] = angle2hms(config.latitude);
        config.latitude = [ d m s ];
      end
      if numel(config.latitude) == 3
        queue(self, 'set_site_latitude', round(config.latitude));
        pause(0.1)
        if isobject(self.private.skychart)
          sc = self.private.skychart;
          sc.place(2) = hms2angle(config.latitude);
        end
      end
    otherwise
      disp([ mfilename ': WARNING: settings: ignoring unkown ' f{1} ' parameter.' ]);
    end % switch
  end % for

  % always sync date, time, daylight saving shift.
  if ~isfield(config, 'UTCoffset')
    config.UTCoffset = self.UTCoffset;
  end
  
  config.UTCoffset          = str2double(config.UTCoffset);
  t0=clock; 
  write(self, 'set_date', round(t0(1:3)));
  write(self, 'set_time', round(t0(4:6)));
  % 'set_UTCoffset',                'SG %+03d',   '','set UTC offset(hh)';
  write(self, 'set_UTCoffset', round(self.UTCoffset));
  % display date/time settings
  t0(4)=t0(4)-self.UTCoffset; % allows to compute properly the Julian Day from Stellarium
  time(self, t0, 'home'); % sets LST
  time(self, t0, 'time'); % sets time and date

end % settings_apply
