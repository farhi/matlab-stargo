function update_status(self)
  % UPDATE_STATUS transfer main controller status to readable fields
  %   RA DEC stored as string for e.g. display in interfaces
  
  t0     = self.private.lastUpdate;
  ra_deg = self.private.ra_deg;
  dec_deg= self.private.dec_deg;
  
  self.state.date = datestr(now);
  
  if isfield(self.state, 'get_radec') && numel(self.state.get_radec) == 2
    self.private.ra_deg  = double(self.state.get_radec(1))/1e6; % in [hours]
    self.private.dec_deg = double(self.state.get_radec(2))/1e5; % in [deg]
    [h1,m1,s1] = angle2hms(self.private.ra_deg,'deg');  % in deg
    [h2,m2,s2] = angle2hms(abs(self.private.dec_deg),'deg');
    self.private.ra_deg = self.private.ra_deg*15; % in [deg]
    if self.state.get_radec(2) < 0, sig = '-'; else sig=''; end
    self.ra  = sprintf('%d:%d:%.1f', h1,m1,s1);
    self.dec = sprintf('%c%d°%d:%.1f', sig, h2,m2,s2);
  elseif  isfield(self.state, 'get_ra') || isfield(self.state, 'get_dec')
    if isfield(self.state, 'get_ra')
      self.ra = sprintf('%d:%d:%.1f', self.state.get_ra);
      self.private.ra_deg  = hms2angle(self.state.get_ra)*15;
    end
    if isfield(self.state, 'get_dec')
      self.dec= sprintf('%d°%d:%.1f', abs(self.state.get_dec)); % the sign may be lost here
      if any(self.state.get_dec < 0) self.dec = [ '-' self.dec ]; end
      self.private.dec_deg = hms2angle(self.state.get_dec);
    end
  end
  
  % compute speed using elapsed time
  
  self.private.lastUpdate= clock;
  if ~isempty(t0) && etime(self.private.lastUpdate,t0) > 0
    dt = etime(self.private.lastUpdate,t0);
    self.private.ra_speed = abs(self.private.ra_deg - ra_deg)/dt;
    self.private.dec_speed= abs(self.private.dec_deg- dec_deg)/dt;
  end

  % motor state and mount status: get_alignment, get_park
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
      self.private.ra_move = self.state.get_motors(1);
      self.private.dec_move= self.state.get_motors(2);
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
  if ~isfield(self.state,'get_motors') || numel(self.state.get_motors) ~= 2
    if isfield(self.state, 'get_motor_status') && numel(self.state.get_motor_status) >= 2
      % [motors=OFF,DEC,RA,all_ON; track=OFF,Moon,Sun,Star; speed=Guide,Center,Find,Max]
      if     self.state.get_motor_status(1) == 0, self.status = 'STOPPED';
      elseif self.state.get_motor_status(1) > 0,  self.status = 'TRACKING';
      end
    end
  end
  if isfield(self.state, 'get_motor_status') && numel(self.state.get_motor_status) >= 3
    self.private.zoom = self.state.get_motor_status(3)+1; % slew speed in 1:4
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
end % update_status
