import os

f = 'lib/services/player_service.dart'
with open(f, 'r') as file:
    content = file.read()

content = content.replace(r'\n', '\n')

with open(f, 'w') as file:
    file.write(content)
