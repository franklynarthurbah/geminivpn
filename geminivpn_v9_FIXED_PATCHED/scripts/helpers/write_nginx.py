import sys
content = open(__file__.replace('write_nginx.py','_nginx_conf.txt')).read()
dest = sys.argv[1] if len(sys.argv) > 1 else '/tmp/nginx.conf'
with open(dest, 'w') as f:
    f.write(content)
print('nginx.conf written to', dest)
