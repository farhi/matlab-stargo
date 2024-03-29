function config=settings_dialogue(self)
  % SETTINGS_DIALOGUE display a dialogue with mount settings and return a struct
  % with changed parameters.
  
  % pop-up choices must start with the current one
    config_meridian = {'auto (flip after passing meridian)','off (disable flip)','forced (flip before reaching meridian)'};
    index = strcmp(strtok(config_meridian), meridianflip(self));
    config_meridian = config_meridian([ find(index) find(~index) ]);
    
    config_tracking = {'on','off','sidereal (stars)','lunar','solar'};
    index = strcmp(strtok(config_tracking), tracking(self));
    config_tracking = config_tracking([ find(index) find(~index) ]);
    
    config_slew_val = [ 6 8 9 12 ];
    config_slew={'low (6)','medium (8)','fast (9,default)','fastest (12, only on 15-18 V)'}; % from get_system_speed_slew
    if isfield(self.state,'get_system_speed_slew') && numel(self.state.get_system_speed_slew) == 2
      index = config_slew_val == self.state.get_system_speed_slew(1);
      config_slew = config_slew([ find(index) find(~index) ]);
    end

    if self.state.get_alignment{1} == 'A'
      config_equalt = {'AltAz','Equatorial'};
    else
      config_equalt = {'Equatorial','AltAz'};
    end

    % display dialogue in non-modal to allow background tasks
    % update is done with CloseReqFcn
    [~,fig,config] = settingsdlg( ...
      'title',[ mfilename ': Avalon mount settings' ], ...
      'Description',[ 'Please check/update the ' mfilename ...
                      ' configuration for ' self.version ], ...
      'WindowStyle','normal', ...
      {'Longitude [HH MM SS]','longitude'}, num2str(self.state.get_site_longitude), ...
      {'Latitude [DD MM SS]','latitude'}, num2str(self.state.get_site_latitude), ...
      {'UTC offset (dayligh saving)','UTCoffset'}, self.UTCoffset, ...
      {'Tracking','tracking'}, config_tracking, ...
      {'Polar scope LED light level [in %]','polar_led'},{'0 (off)','10','20','30','40','50','60','70','80','90'}, ...
      'separator','   ', ...
      {'Meridian flip','meridianflip'}, config_meridian, ...
      {'ST4 port connected','st4'}, logical(self.state.get_st4), ...
      {'Keypad connected','keypad'}, logical(self.state.get_keypad), ...
      {'Equatorial/Alt-Az mode','mode'}, config_equalt, ...
      {'Hemisphere','hemisphere'}, {'unset','North','South'}, ...
      'separator','Advanced settings', ...
      {'Mount gear ratio','mount_gear_ratio'},{'unset','1 (M-zero:385.027)','2 (576)','3 (Linear,M-uno,EQ6:705.882)','4 (720)','5 (645)','6 (1440)','7 (Omega:1200 1000)','8 (B230: 720 570)'}, ...
      {'Motor torque','motor_torque'}, {'unset','50 % (M-zero)','70 % (Linear,M-uno)'}, ...
      {'Auto guiding speed [RA DEC, in % of sidereal speed, e.g. 30 stands for 0.30]','autoguiding_speed'}, num2str(self.state.get_autoguiding_speed), ...
      {'Reverse RA/DEC', 'reverse_radec'}, {'unset','normal','RA reversed','DEC reversed', 'RA/DEC reversed'}, ...
      {'System speed: center','system_speed_center'}, {'unset','2','3','4','6 (default)','8','10'}, ...
      {'System speed: guide','system_speed_guide'},  {'unset','10','15','20','30 (default)','50','75','100','150'}, ...
      {'System speed: slew (directional arrows)', 'system_speed_slew'}, config_slew ...
    );
    % apply changed members when deleting settings window
    set(fig, 'DeleteFcn', @(src,evnt)settings(self, fig, config));
    
  end % settings_dialogue
