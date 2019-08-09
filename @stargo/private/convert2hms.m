function [h,m,s] = convert2hms(in,hours)
  h=[]; m=[]; s=[];
  if nargin < 2, hours='hours'; end
  if isempty(in), return; end
  if ischar(in) % from HH:MM:SS
    str = repradec(in);
    if isnumeric(str) && all(isfinite(str))
      in = str;
    end
  end
  if isnumeric(in) 
    if isscalar(in)
      [h,m,s] = angle2hms(in,hours);
    elseif numel(in) == 3
      h=in(1); m=in(2); s=in(3);
    end
  end
end % convert2hms
