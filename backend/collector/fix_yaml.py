with open('sources.yaml', 'r') as f:
    lines = f.readlines()

draw_idx = -1
for i, line in enumerate(lines):
    if line.startswith('draw:'):
        draw_idx = i
        break

appended_start = -1
for i in range(draw_idx, len(lines)):
    if line.startswith('  - source_id: facai_xianfeng'):
        appended_start = i
        break

# Actually it's easier to just find the first added source: `  - source_id: facai_xianfeng`
for i, line in enumerate(lines):
    if line.startswith('  - source_id: facai_xianfeng'):
        appended_start = i
        break

if appended_start != -1 and appended_start > draw_idx:
    added_lines = lines[appended_start:]
    original_rest = lines[draw_idx:appended_start]
    before = lines[:draw_idx]
    
    new_lines = before + added_lines + original_rest
    with open('sources.yaml', 'w') as f:
        f.writelines(new_lines)
        print("Fixed!")
else:
    print("Could not find properly")
