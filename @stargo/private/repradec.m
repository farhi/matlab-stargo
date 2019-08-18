function str = repradec(str)
  %repradec: replace string stuff and get it into num
  str = strtrim(lower(str));
  for rep = {'h','m','s',':','°','deg','d','''','"','*','[',']'}
    str = strrep(str, rep{1}, ' ');
  end
  str = str2num(str);
end
