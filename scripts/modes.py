"""VESA DMT timing expectations for the vga_text_engine test suite.

Written from the VESA Display Monitor Timing specification, independently of
rtl/vte_modes_pkg.sv. The timing conformance test compares what the RTL actually
produces against these numbers, so a typo in either place shows up as a failure
rather than cancelling out.
"""

# name, pixel clock in MHz, h_active, h_front, h_sync, h_back, h_pos,
#                           v_active, v_front, v_sync, v_back, v_pos
MODES = [
    dict(index=0, name="640x480@60", pclk=25.175,
         h_active=640, h_front=16, h_sync=96, h_back=48, h_pos=0,
         v_active=480, v_front=10, v_sync=2, v_back=33, v_pos=0),
    dict(index=1, name="800x600@60", pclk=40.000,
         h_active=800, h_front=40, h_sync=128, h_back=88, h_pos=1,
         v_active=600, v_front=1, v_sync=4, v_back=23, v_pos=1),
    dict(index=2, name="1024x768@60", pclk=65.000,
         h_active=1024, h_front=24, h_sync=136, h_back=160, h_pos=0,
         v_active=768, v_front=3, v_sync=6, v_back=29, v_pos=0),
    dict(index=3, name="720x400@70", pclk=28.322,
         h_active=720, h_front=18, h_sync=108, h_back=54, h_pos=0,
         v_active=400, v_front=12, v_sync=2, v_back=35, v_pos=1),
]

BY_INDEX = {m["index"]: m for m in MODES}


def h_total(m):
    return m["h_active"] + m["h_front"] + m["h_sync"] + m["h_back"]


def v_total(m):
    return m["v_active"] + m["v_front"] + m["v_sync"] + m["v_back"]


def refresh_hz(m):
    return m["pclk"] * 1e6 / (h_total(m) * v_total(m))
