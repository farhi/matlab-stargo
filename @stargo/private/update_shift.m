function update_shift(self)
  % UPDATE_SHIFT handle shift operation
  %   start, test target values, change speed, test for done
  if isempty(self.private.shift_ra) && isempty(self.private.shift_dec), return; end
  
  % determine direction to go
  if ~isempty(self.private.shift_ra)
    if self.private.shift_ra     > self.private.ra_deg, ra_dir = 'e'; % RA+
    elseif self.private.shift_ra < self.private.ra_deg, ra_dir = 'w'; % RA-
    end
    delta_ra = abs(self.private.ra_deg - self.private.shift_ra);
  else delta_ra = 0; end
  
  if ~isempty(self.private.shift_dec)
    if self.private.shift_dec     > self.private.dec_deg, dec_dir = 'n'; % DEC+
    elseif self.private.shift_dec < self.private.dec_deg, dec_dir = 's'; % DEC-
    end
    delta_dec = abs(self.private.dec_deg - self.private.shift_dec);
  else delta_dec = 0; end

  % are we done ? i.e. smallest zoom level and within 1 sec.
  if delta_ra < self.private.ra_speeds(1)
    disp([ mfilename ': reached RA (shift).' ])
    self.private.shift_ra = [];
  end
  if delta_dec < self.private.dec_speeds(1)
    disp([ mfilename ': reached DEC (shift).' ])
    self.private.shift_dec = [];
  end
  
  % determine if we are there within the accuracy (update timer) and current slew speed
  if ~isempty(self.private.shift_ra) && self.private.ra_speed > 1e-3
    ra_eta = delta_ra/self.private.ra_speed; % in [s]
    if ra_eta < 1, move(self, [ ra_dir ' stop' ]); end
  end
  if ~isempty(self.private.shift_dec) && self.private.dec_speed > 1e-3
    dec_eta = delta_dec/self.private.dec_speed; % in [s]
    if dec_eta < 1, move(self, [ dec_dir ' stop' ]); end
  end
  
  % determine the most appropriate speed for movement
  ra_eta_zoom  = delta_ra ./ self.private.ra_speeds; % decreasing ETA's
  dec_eta_zoom = delta_dec./ self.private.dec_speeds;
  eta_zoom     = max(ra_eta_zoom, dec_eta_zoom);

  % get the eta which is larger than 2 sec
  index = find(eta_zoom > 2);
  if isempty(index), zoom_level = 1; else zoom_level = index(end); end

  % set appropriate zoom level for ETA > 2 or finest accuracy
  if ~isempty(self.private.shift_ra) || ~isempty(self.private.shift_dec)
    zoom(self, zoom_level);
  end
  % trigger move
  if ~isempty(self.private.shift_ra)
    move(self, ra_dir);
  end
  if ~isempty(self.private.shift_dec)
    move(self, dec_dir);
  end
end % update_shift
