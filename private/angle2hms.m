function [h,m,s] = angle2hms(ang,in)
  % angle2hms convert angle from [deg] to hh:mm:ss
  if nargin < 2, in='hours'; end
  if strcmp(in, 'hours')
    ang = ang/15;
  end
  h=fix(ang); m=fix((ang-h)*60); s=(ang-h-m/60)*3600;
end % angle2hms
