---
icon: 💻
lead: Ines
members: 4
meets: Wednesday
building: the telemetry, the shore screen, the race plan
tags:
  - division
---
# Software and telemetry

A small computer on the boat sends speed, battery charge and sun every second to a laptop on the shore, which shows when to go faster and when to save energy.

```python
def minutes_left(charge_wh, power_w):
    return 60 * charge_wh / power_w
```

- [x] Read speed from the GPS
- [ ] Send the battery's charge over the radio
- [ ] Draw both on the shore screen

Back to [[Solar Boat Team]].
