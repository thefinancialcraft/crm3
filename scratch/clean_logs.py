import re
import os

def clean_and_organize_logs(file_path):
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return

    with open(file_path, 'rb') as f:
        raw_content = f.read()

    # 1. Decode and basic cleanup
    content_bytes = raw_content.replace(b'\x00', b'')
    try:
        content = content_bytes.decode('utf-8', errors='ignore')
    except Exception as e:
        print(f"Decode error: {e}")
        return

    # 2. Fix encoding artifacts (spaced out text)
    if "I / f l u t t e r" in content:
        content = re.sub(r'([A-Za-z0-9/\[\]\(\):#.,!_-]) ', r'\1', content)
        content = content.replace('  ', ' ')

    # 3. Remove Control Characters and ANSI
    content = "".join(ch for ch in content if ord(ch) >= 32 or ch in "\n\r\t")
    content = re.sub(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])', '', content)
    content = re.sub(r'\[\d+(?:;\d+)*m', '', content)

    # 4. Map corrupted special characters - Extended list
    replacements = {
        'Γöî': '┌', 'ΓöÇ': '─', 'Γöé': '│', 'Γö£': '├', 'Γöä': '─', 'Γöö': '└',
        'ΓòÉ': '═', 'Γòí': '╗', 'Γò₧': '╝', 'Γä': '─', 'ΓêÜ': '√',
        '≡ƒÜÇ': '🚀', '≡ƒÆô': '💓', '≡ƒÆí': '💡', '≡ƒöä': '🔄', '≡ƒôñ': '📤',
        'Γ£à': '✅', '≡ƒô▒': '📱', '≡ƒô₧': '📞', '≡ƒôÑ': '📥', '≡ƒöù': '🔗',
        '≡ƒöÉ': '🔐', '≡ƒ¢á∩╕Å': '🛠️', '≡ƒƒó': '🟢', '≡ƒôì': '🔍', '≡ƒôí': '📡',
        'a" a"': '─', 'a"': '─', 'â"': '─', 'â"â"': '──',
    }
    for target, replacement in replacements.items():
        content = content.replace(target, replacement)

    # 5. Logical Organization
    lines = content.splitlines()
    organized_lines = []
    
    heartbeat_count = 0
    
    for line in lines:
        line = line.strip()
        if not line: continue
        
        # Strip Android logging prefixes
        line = re.sub(r'^I/flutter\s*\(\d+\):\s*', '', line)
        line = re.sub(r'^D/flutter/[A-Z_]+\s*\(\d+\):\s*', '', line)
        line = re.sub(r'^D/CallBridgePlugin\s*\(\d+\):\s*', '', line)
        line = re.sub(r'^D/FlutterJNI\s*\(\d+\):\s*', '', line)

        # Handle stack traces - indent them
        if re.match(r'^#\d+\s+', line):
            organized_lines.append("    " + line)
            continue

        # Strip internal box markers for cleaner categorization
        clean_msg = line
        if clean_msg.startswith('│'):
            clean_msg = clean_msg[1:].strip()
        
        # Handle Heartbeat Pulse - collapse multiples
        if "Sync: Heartbeat pulse" in clean_msg:
            heartbeat_count += 1
            if heartbeat_count == 1:
                organized_lines.append("💓 [HEARTBEAT] " + clean_msg)
            continue
        else:
            if heartbeat_count > 1:
                # Add count to the previous heartbeat line
                organized_lines[-1] = organized_lines[-1] + f" (x{heartbeat_count})"
            heartbeat_count = 0

        # Don't add icons to box lines
        if any(c in line for c in '┌┐└┘├┤─═║'):
            organized_lines.append(line)
            continue

        # Categorize known tags
        if "[FUNCTION:" in clean_msg:
            clean_msg = clean_msg.replace("[FUNCTION:", "⚙️ [FUNC:")
        elif "[UI]" in clean_msg:
            clean_msg = clean_msg.replace("[UI]", "📱 [UI]")
        elif "Sync:" in clean_msg:
            clean_msg = "🔄 [SYNC] " + clean_msg.replace("Sync:", "").strip()
        elif "App:" in clean_msg:
            clean_msg = "🚀 [APP] " + clean_msg.replace("App:", "").strip()
        elif "Call Event:" in clean_msg:
            clean_msg = "📞 [CALL] " + clean_msg.replace("Call Event:", "").strip()
        elif "WebBridge" in clean_msg:
            clean_msg = "🌉 [BRIDGE] " + clean_msg
        
        # Clean up residual junk characters at the start
        clean_msg = re.sub(r'^─\s+', '─ ', clean_msg)
        clean_msg = re.sub(r'^─[^\s\[A-Za-z]+', '─ ', clean_msg)
        
        # If it was a box line content, maybe keep the bar?
        if line.startswith('│'):
            organized_lines.append("│ " + clean_msg)
        else:
            organized_lines.append(clean_msg)

    # Final join and cleanup
    final_content = "\n".join(organized_lines)
    
    # Remove excessive blank lines
    final_content = re.sub(r'\n{3,}', '\n\n', final_content)

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(final_content)
    
    print(f"Successfully cleaned and organized: {file_path}")

if __name__ == "__main__":
    log_path = r"c:\flutter\crm3v2 - Copy\build_logs.txt"
    clean_and_organize_logs(log_path)
