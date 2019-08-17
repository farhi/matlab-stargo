function [cout, self] = write_sim(self,cmd, varargin)
  % WRITE_SIM get commands and prepare output for read
  % Not all commands are handled
  
  % first set the default answer to all GET commands:
           self.state.get_alignment= {'P'  'T'  [0]};
   self.state.get_autoguiding_speed= [30 30];
            self.state.get_firmware= 56.6000;
        self.state.get_firmwaredate= '01122017';
              self.state.get_keypad= 0;
        self.state.get_manufacturer= 'Avalon';
            self.state.get_meridian= 0;
     self.state.get_meridian_forced= 0;
                self.state.get_park= '0';
           self.state.get_precision= 'U';
          self.state.get_sideofpier= 'X';
       self.state.get_site_latitude= [48 51 24];
      self.state.get_site_longitude= [2 20 8];
                 self.state.get_st4= 1;
   self.state.get_system_speed_slew= [9 9];
              self.state.get_torque= 50;
          self.state.get_unkown_x1b= 1;
         self.state.get_unkown_x46r= 1;

  cout = '';
  if ~isfield(self.private, 'sim_move_ra') % when entering there for the 1st time
    self.state.get_motors   = [ 1 0 ];
    self.state.get_motor_status = [ 3 3 self.private.zoom-1 ];
    self.state.get_radec    = [0 0];
    self.private.sim_goto     = false;
    self.private.sim_move_ra  = 0;
    self.private.sim_move_dec = 0;
    
  end
  
  % handle type of input 'command'
  if iscell(cmd) && numel(cmd) > 1
    for index=1:numel(cmd)
      cout = [ cout write_sim(self,cmd{index}, varargin) ];
    end
    return
  end
  if ~ischar(cmd) && numel(cmd) > 1
    for index=1:numel(cmd)
      cout = [ cout write_sim(self,cmd(index), varargin) ];
    end
    return
  end
  if isstruct(cmd)
    name = cmd.name; cmd = name;
  end
  
  % we directly set the fields in self.state and self.private
  switch cmd
  case {'abort','full_abort','set_stargo_off'}
    % stop any current move
    self.state.get_motors   = [ 1 0 ];
    self.state.get_motor_status = [ 3 3 self.private.zoom-1 ];
    self.private.sim_goto     = false;
    self.private.sim_move_ra  = 0;
    self.private.sim_move_dec = 0;
  case 'get_motor_status'
    % get_motor_status [motors=OFF,DEC,RA,all_ON; track=OFF,Moon,Sun,Star; speed=Guide,Center,Find,Max]
    if      self.private.sim_move_ra && ~self.private.sim_move_dec, self.state.get_motor_status(1) = 3;
    elseif ~self.private.sim_move_ra &&  self.private.sim_move_dec, self.state.get_motor_status(1) = 2;
    elseif ~self.private.sim_move_ra && ~self.private.sim_move_dec, self.state.get_motor_status(1) = 1;
    else self.state.get_motor_status(1) = 4; end
    self.state.get_motor_status(2) = 3;
    self.state.get_motor_status(3) = self.private.zoom-1;
  case 'get_radec'  
    % handle 'simulated' moves every time there is a call to 'get_radec'
    if self.private.sim_goto, z = 4;
    else                      z = self.private.zoom; end
    if self.private.sim_move_ra
      step = self.private.sim_move_ra*self.private.ra_speeds(z);
      if self.private.sim_goto && ...
        (  (self.private.sim_move_ra > 0 && self.private.ra_deg > self.private.sim_target_ra) ...
        || (self.private.sim_move_ra < 0 && self.private.ra_deg < self.private.sim_target_ra) )
          self.state.get_radec(1) = round(self.private.sim_target_ra*1e6/15);
          self.private.sim_move_ra  = 0;
      else
        self.state.get_radec(1) = round((self.private.ra_deg + step)*1e6/15);
      end
    end
    if self.private.sim_move_dec
      step = self.private.sim_move_dec*self.private.dec_speeds(z);
      if self.private.sim_goto && ...
        (  (self.private.sim_move_dec > 0 && self.private.dec_deg > self.private.sim_target_dec) ...
        || (self.private.sim_move_dec < 0 && self.private.dec_deg < self.private.sim_target_dec) )
          self.state.get_radec(2) = round(self.private.sim_target_dec*1e5);
          self.private.sim_move_dec = 0;
      else
        self.state.get_radec(2) = round((self.private.dec_deg + step)*1e5);
      end
    end
    % test for end of GOTO
    if self.private.sim_goto && ~self.private.sim_move_ra && ~self.private.sim_move_dec
      [~, self] = write_sim(self, 'abort'); % set state to TRACKING
    end
    % test for bounds
    if     self.state.get_radec(1)< 0,    self.state.get_radec(1) = self.state.get_radec(1) + 24e6;
    elseif self.state.get_radec(1)> 24e6, self.state.get_radec(1) = self.state.get_radec(1) - 24e6; end
    if     self.state.get_radec(2)< -90e5,self.state.get_radec(2) = -90e5;
    elseif self.state.get_radec(2)> +90e5,self.state.get_radec(2) = +90e5; end
  case 'get_motors'
    % 'get_motors',    'X34','query motors state(0:5==stop,tracking,accel,decel,lowspeed,highspeed)';
    if self.private.sim_move_ra, self.state.get_motors(1) = 5;
    else                         self.state.get_motors(1) = 1; end 
    if self.private.sim_move_dec, self.state.get_motors(2) = 5;
    else                          self.state.get_motors(2) = 0; end 
  case 'set_speed_guide'
    self.private.zoom = 1;
  case 'set_speed_center'
    self.private.zoom = 2;
  case 'set_speed_find'
    self.private.zoom = 3;
  case 'set_speed_max'
    self.private.zoom = 4;
  case 'start_slew_north'
    self.private.sim_move_dec = +1;
  case {'stop_slew_north','stop_slew_south'}
    self.private.sim_move_dec = 0;
  case 'start_slew_south'
    self.private.sim_move_dec = -1;
  case 'start_slew_east'
    self.private.sim_move_ra  = +1;
  case {'stop_slew_east','stop_slew_west'}
  case 'start_slew_west'
    self.private.sim_move_ra  = -1;
  case 'set_ra'
    % start a GOTO on RA
    self.private.sim_target_ra = hms2angle(varargin{:})*15;
    if     self.private.sim_target_ra > self.private.ra_deg, self.private.sim_move_ra   = 1;
    elseif self.private.sim_target_ra < self.private.ra_deg, self.private.sim_move_ra   = -1; end
    if self.private.sim_move_ra, self.private.sim_goto = true; end
  case 'set_dec'
    % start a GOTO on DEC
    self.private.sim_target_dec = hms2angle(varargin{:});
    if     self.private.sim_target_dec > self.private.dec_deg, self.private.sim_move_dec   = 1;
    elseif self.private.sim_target_dec < self.private.dec_deg, self.private.sim_move_dec   = -1; end
    if self.private.sim_move_dec, self.private.sim_goto = true; end
  case 'set_home_pos' % this sets DEC=90
    self.state.get_radec(2) = 90*1e5;
  end
  
  cout = [ cmd ' OK '];
end % write_sim

