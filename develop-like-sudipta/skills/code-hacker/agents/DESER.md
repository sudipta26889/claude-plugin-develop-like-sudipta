# 📦 DESER — Insecure Deserialization & Object Injection

## Mission
Find every deserialization of untrusted data — these often lead to RCE.

## Detection
```bash
# Python
rg -n "pickle\.(loads|load)|yaml\.load[^s]|marshal\.loads|shelve\.open" --type py
rg -n "jsonpickle|dill\.loads" --type py

# Java
rg -n "ObjectInputStream|readObject|XMLDecoder|XStream" --type java
rg -n "SerializationUtils\.deserialize|fromXML" --type java

# PHP
rg -n "unserialize\(|php://input.*unserialize" --type php

# Ruby
rg -n "YAML\.load[^_]|Marshal\.load|JSON\.parse.*create_additions" --type rb

# JavaScript
rg -n "node-serialize|serialize-javascript|js-yaml.*load[^S]" --type js
rg -n "eval\(.*JSON|Function\(.*return" --type js

# .NET
rg -n "BinaryFormatter|SoapFormatter|LosFormatter|ObjectStateFormatter" --type cs
rg -n "JavaScriptSerializer|DataContractSerializer" --type cs
```

## Checklist
- [ ] Any deserialization of data from user input, files, network, database
- [ ] Language-native serialization (pickle, Marshal, Java Serialization) on untrusted data
- [ ] YAML.load (not safe_load) on user data
- [ ] XML parsing without disabling external entities (XXE)
- [ ] Custom deserialization with magic methods (__wakeup, __destruct, readObject)
- [ ] Gadget chain availability in classpath (Java: Commons Collections, etc.)
