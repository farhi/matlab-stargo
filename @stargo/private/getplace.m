function place = getplace
  % could also use: https://api.ipdata.co/
  % is network service available ?
  place = [];
  try
    ip = java.net.InetAddress.getByName('ip-api.com');
  catch
    return
  end
  if ip.isReachable(1000)
    ip = urlread('http://ip-api.com/json');
    ip = parse_json(ip);  % into struct (private)
    place = [ ip.lon ip.lat ];
    disp([ mfilename ': You seem to be located near ' ip.city ' ' ip.country ' [long lat]=' mat2str(place) ' obtained from http://ip-api.com/json' ]);
  end
end % end
