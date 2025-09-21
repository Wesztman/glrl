# glrl - Green light/Red light

Green light/Red light, or glrl in short, is a simple status monitor written in bash. Use it to monitor anything that can evaluate into a bash boolean expression.

Use config.yaml to list bash commands that evaluate to true or false (auto reloads on changes while running) 

```yaml
- title: "NS1"
  checks:
    - name: "ns1 - exists"
      command: "ip netns list | grep -q '^ns1'"
    - name: "ns1 - usb1 exists"
      command: "ip netns exec ns1 ip addr show 2>/dev/null | grep -q usb1"
    - name: "ns1 - usb1 is UP"
      command: "ip netns exec ns1 ip addr show 2>/dev/null | grep usb1 | grep -q 'state UP'"
- title: "NS2"
  checks:
    - name: "ns2 - exists"
      command: "ip netns list | grep -q '^ns2'"
    - name: "ns2 - usb2 exists"
      command: "ip netns exec ns2 ip addr show 2>/dev/null | grep -q usb2"
    - name: "ns2 - usb2 is UP"
      command: "ip netns exec ns2 ip addr show 2>/dev/null | grep usb2 | grep -q 'state UP'"
```

Next run

`./glrl.sh`

or in the above example with network namespaces

`sudo ./glrl.sh`

since it needs to run `ip netns exec`.

and glrl will show the current status.

![image.png](docs/image.png)

A timer exists to make sure that the screen is not frozen.
