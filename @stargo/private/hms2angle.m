function ang = hms2angle(h,m,s)
  % hms2angle convert hh:mm:ss to an angle in [deg]
  if nargin == 1 && numel(h) == 3
    m = h(2); s=h(3); h=h(1);
  end
  ang = double(h) + double(m)/60 + double(s)/3600;
end % hms2angle
