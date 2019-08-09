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
  end
  
  if ~isempty(self.private.shift_dec)
    if self.private.shift_dec     > self.private.dec_deg, dec_dir = 'n'; % DEC+
    elseif self.private.shift_dec < self.private.dec_deg, dec_dir = 's'; % DEC-
    end
    delta_dec = abs(self.private.dec_deg - self.private.shift_dec);
  end
  
  % determine if we are there within the accuracy (update timer) and current slew speed
  if ~isempty(self.private.shift_ra) && self.private.ra_speed > 1e-2
    ra_eta = delta_ra/self.private.ra_speed; % in [s]
    if ra_eta < 1, move(self, [ ra_dir ' stop' ]); end
  end
  if ~isempty(self.private.shift_dec) && self.private.dec_speed > 1e-2
    dec_eta = delta_dec/self.private.dec_speed; % in [s]
    if dec_eta < 1, move(self, [ dec_dir ' stop' ]); end
  end
  
  % determine the most appropriate speed for movement
  
end % update_shift
