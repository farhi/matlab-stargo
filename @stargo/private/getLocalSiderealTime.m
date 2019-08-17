function [LST, JD, GST] = getLocalSiderealTime(longitude, t0)
  % getLocalSiderealTime compute LST
  %   getLocalSiderealTime(longitude, [year month day hour minute seconds]) uses
  %   specified date and time.
  %
  %   getLocalSiderealTime(longitude) uses current date and time (but does not 
  %   correct for UTC offset).
  if nargin < 1
    longitude = 2;
  end
  if nargin <= 1
    t0 = clock;
  end
  fprintf('Date                               %s\n', datestr(t0));
  year=t0(1); month=t0(2);  day=t0(3); 
  hour=t0(4);   min=t0(5);  sec=t0(6); 
  UT = hour + min/60 + sec/3600;
  J0 = 367*year - floor(7/4*(year + floor((month+9)/12))) ...
      + floor(275*month/9) + day + 1721013.5;
  JD = J0 + UT/24;              % Julian Day
  fprintf('Julian day                         %6.4f [days]\n',JD);
  JC = (J0 - 2451545.0)/36525;
  GST0 = 100.4606184 + 36000.77004*JC + 0.000387933*JC^2 - 2.583e-8*JC^3; %[deg]
  GST0 = mod(GST0, 360);  % GST0 range [0..360]
  fprintf('Greenwich sidereal time at 0 hr UT %6.4f [deg]\n',GST0);
  GST = GST0 + 360.98564724*UT/24;
  GST = mod(GST, 360);  % GST range [0..360]
  fprintf('Greenwich sidereal time at UT[h]   %6.4f [deg]\n',GST);
  LST = GST + longitude;
  LST = mod(LST, 360);  % LST range [0..360]
  fprintf('Local sidereal time                %6.4f [deg]\n',LST);
  [h,m,s] = angle2hms(LST);
  fprintf('                                   %2d:%2d:%2d\n',h,m,round(s));
end % getLocalSiderealTime
