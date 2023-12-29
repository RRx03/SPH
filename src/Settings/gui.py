from tkinter import *
from json import *
from random import *


jsonDICO = {
    "SECURITY": 1,
    "RESET": 0,
    "PARTICLECOUNT": 8000,
    "RADIUS": 0.2,
    "H": 0.6,
    "TARGET_DENSITY": 1,
    "GAZ_CONSTANT": 100,
    "NEAR_GAZ_CONSTANT": 100,
    "VISCOSITY": 1,
    "DUMPING_FACTOR": 0.95,
    "FREQUENCY": 0.0,
    "AMPLITUDE": 0.0,
    "PAUSE": 0,
}

packCount = 4
spaceSizing = 10


settings = open("./src/Settings/settings.json", "w")
settings.write(dumps(jsonDICO))
settings.close()
master = Tk()


def setValues():
    RADIUS.set(jsonDICO["RADIUS"])
    H.set(jsonDICO["H"])
    TARGET_DENSITY.set(jsonDICO["TARGET_DENSITY"])
    GAZ_CONSTANT.set(jsonDICO["GAZ_CONSTANT"])
    NEAR_GAZ_CONSTANT.set(jsonDICO["NEAR_GAZ_CONSTANT"])
    VISCOSITY.set(jsonDICO["VISCOSITY"])
    DUMPING_FACTOR.set(jsonDICO["DUMPING_FACTOR"])
    FREQUENCY.set(jsonDICO["FREQUENCY"])
    AMPLITUDE.set(jsonDICO["AMPLITUDE"])
    PARTICLECOUNT.set(jsonDICO["PARTICLECOUNT"])
    PAUSE.set(jsonDICO["PAUSE"])


def updateSettings(event):
    sendUpdates()


def sendUpdates():
    jsonDICO["RADIUS"] = RADIUS.get()
    jsonDICO["H"] = H.get()
    jsonDICO["TARGET_DENSITY"] = TARGET_DENSITY.get()
    jsonDICO["GAZ_CONSTANT"] = GAZ_CONSTANT.get()
    jsonDICO["NEAR_GAZ_CONSTANT"] = NEAR_GAZ_CONSTANT.get()
    jsonDICO["VISCOSITY"] = VISCOSITY.get()
    jsonDICO["DUMPING_FACTOR"] = DUMPING_FACTOR.get()
    jsonDICO["FREQUENCY"] = FREQUENCY.get()
    jsonDICO["AMPLITUDE"] = AMPLITUDE.get()
    jsonDICO["PARTICLECOUNT"] = PARTICLECOUNT.get()
    jsonDICO["PAUSE"] = PAUSE.get()
    jsonDICO["SECURITY"] = random()
    settings = open("./src/Settings/settings.json", "w")
    settings.write(dumps(jsonDICO))
    settings.close()


def resetButton():
    jsonDICO["RESET"] = 1 * (not jsonDICO["RESET"])
    sendUpdates()


master.geometry("+850+0")
master.geometry("850x900")
master.title("GUI")
master.configure(bg="white")
master.grid_columnconfigure(0, weight=1)


PARTICLECOUNT = DoubleVar()
RADIUS = DoubleVar()
H = DoubleVar()
TARGET_DENSITY = DoubleVar()
GAZ_CONSTANT = DoubleVar()
NEAR_GAZ_CONSTANT = DoubleVar()
VISCOSITY = DoubleVar()
DUMPING_FACTOR = DoubleVar()
FREQUENCY = DoubleVar()
AMPLITUDE = DoubleVar()
DENSITYVISUAL = DoubleVar()
PRESSUREVISUAL = DoubleVar()
SPEEDVISUAL = DoubleVar()
PAUSE = DoubleVar()


currentRow = 0
Label(master, text="PARTICLECOUNT").grid(row=packCount * currentRow, column=0)
E0 = Entry(master, textvariable=PARTICLECOUNT, bd=0, justify="center")
E0.bind("<Return>", updateSettings)
E0.grid(row=packCount * currentRow + 1, column=0)
master.rowconfigure(currentRow * packCount + 2, minsize=spaceSizing)


currentRow += 1
Label(master, text="RADIUS").grid(row=packCount * currentRow, column=0)
Scale(
    master,
    from_=0,
    to=2,
    length=800,
    orient=HORIZONTAL,
    resolution=0.01,
    command=updateSettings,
    variable=RADIUS,
    bg="white",
    bd=1,
    showvalue=0,
    troughcolor="lightgrey",
).grid(row=packCount * currentRow + 1, column=0)
E1 = Entry(master, textvariable=RADIUS, bd=0, justify="center")
E1.bind("<Return>", updateSettings)
E1.grid(row=packCount * currentRow + 2, column=0)
master.rowconfigure(currentRow * packCount + 3, minsize=spaceSizing)


currentRow += 1
Label(master, text="H").grid(row=packCount * currentRow, column=0)
Scale(
    master,
    from_=0.01,
    to=2,
    length=800,
    orient=HORIZONTAL,
    resolution=0.01,
    command=updateSettings,
    variable=H,
    bg="white",
    bd=1,
    showvalue=0,
    troughcolor="lightgrey",
).grid(row=packCount * currentRow + 1, column=0)
E2 = Entry(master, textvariable=H, bd=0, justify="center")
E2.bind("<Return>", updateSettings)
E2.grid(row=packCount * currentRow + 2, column=0)
master.rowconfigure(currentRow * packCount + 3, minsize=spaceSizing)

currentRow += 1
Label(master, text="TARGET_DENSITY").grid(row=packCount * currentRow, column=0)
Scale(
    master,
    from_=0,
    to=1000,
    length=800,
    orient=HORIZONTAL,
    resolution=1,
    command=updateSettings,
    variable=TARGET_DENSITY,
    bg="white",
    bd=1,
    showvalue=0,
    troughcolor="lightgrey",
).grid(row=packCount * currentRow + 1, column=0)
E3 = Entry(master, textvariable=TARGET_DENSITY, bd=0, justify="center")
E3.bind("<Return>", updateSettings)
E3.grid(row=packCount * currentRow + 2, column=0)
master.rowconfigure(currentRow * packCount + 3, minsize=spaceSizing)


currentRow += 1
Label(master, text="GAZ_CONSTANT").grid(row=packCount * currentRow, column=0)
Scale(
    master,
    from_=0,
    to=1000,
    length=800,
    orient=HORIZONTAL,
    resolution=1,
    command=updateSettings,
    variable=GAZ_CONSTANT,
    bg="white",
    bd=1,
    showvalue=0,
    troughcolor="lightgrey",
).grid(row=packCount * currentRow + 1, column=0)
E4 = Entry(master, textvariable=GAZ_CONSTANT, bd=0, justify="center")
E4.bind("<Return>", updateSettings)
E4.grid(row=packCount * currentRow + 2, column=0)
master.rowconfigure(currentRow * packCount + 3, minsize=spaceSizing)


currentRow += 1
Label(master, text="NEAR_GAZ_CONSTANT").grid(row=packCount * currentRow, column=0)
Scale(
    master,
    from_=0,
    to=1000,
    length=800,
    orient=HORIZONTAL,
    resolution=1,
    command=updateSettings,
    variable=NEAR_GAZ_CONSTANT,
    bg="white",
    bd=1,
    showvalue=0,
    troughcolor="lightgrey",
).grid(row=packCount * currentRow + 1, column=0)
E5 = Entry(master, textvariable=NEAR_GAZ_CONSTANT, bd=0, justify="center")
E5.bind("<Return>", updateSettings)
E5.grid(row=packCount * currentRow + 2, column=0)
master.rowconfigure(currentRow * packCount + 3, minsize=spaceSizing)


currentRow += 1
Label(master, text="VISCOSITY").grid(row=packCount * currentRow, column=0)
Scale(
    master,
    from_=0,
    to=10,
    length=800,
    orient=HORIZONTAL,
    resolution=0.01,
    command=updateSettings,
    variable=VISCOSITY,
    bg="white",
    bd=1,
    showvalue=0,
    troughcolor="lightgrey",
).grid(row=packCount * currentRow + 1, column=0)
E6 = Entry(master, textvariable=VISCOSITY, bd=0, justify="center")
E6.bind("<Return>", updateSettings)
E6.grid(row=packCount * currentRow + 2, column=0)
master.rowconfigure(currentRow * packCount + 3, minsize=spaceSizing)

currentRow += 1
Label(master, text="DUMPING_FACTOR").grid(row=packCount * currentRow, column=0)
Scale(
    master,
    from_=0,
    to=1,
    length=800,
    orient=HORIZONTAL,
    resolution=0.01,
    command=updateSettings,
    variable=DUMPING_FACTOR,
    bg="white",
    bd=1,
    showvalue=0,
    troughcolor="lightgrey",
).grid(row=packCount * currentRow + 1, column=0)
E7 = Entry(master, textvariable=DUMPING_FACTOR, bd=0, justify="center")
E7.bind("<Return>", updateSettings)
E7.grid(row=packCount * currentRow + 2, column=0)
master.rowconfigure(currentRow * packCount + 3, minsize=spaceSizing)

currentRow += 1
Label(master, text="FREQ & AMP").grid(row=packCount * currentRow, column=0)
E8 = Entry(master, textvariable=FREQUENCY, bd=0, justify="center")
E8.bind("<Return>", updateSettings)
E8.grid(row=packCount * currentRow + 1, column=0)
E9 = Entry(master, textvariable=AMPLITUDE, bd=0, justify="center")
E9.bind("<Return>", updateSettings)
E9.grid(row=packCount * currentRow + 2, column=0)
master.rowconfigure(currentRow * packCount + 3, minsize=spaceSizing)


currentRow += 1
C1 = Checkbutton(
    master, text="Density", variable=DENSITYVISUAL, onvalue=1, offvalue=0
).grid(row=packCount * currentRow, column=0)
C2 = Checkbutton(
    master, text="Pressure", variable=PRESSUREVISUAL, onvalue=1, offvalue=0
).grid(row=packCount * currentRow + 1, column=0)
C3 = Checkbutton(
    master, text="Velocity", variable=SPEEDVISUAL, onvalue=1, offvalue=0
).grid(row=packCount * currentRow + 2, column=0)
C4 = Checkbutton(master, text="LEAPFROG", variable=None, onvalue=1, offvalue=0).grid(
    row=packCount * currentRow + 3, column=0
)

currentRow += 1
pauseButton = Checkbutton(
    master, text="PAUSE", variable=PAUSE, onvalue=1, offvalue=0, command=sendUpdates
).grid(row=packCount * currentRow, column=0)


currentRow += 1
send = Button(master, text="SEND", command=sendUpdates).grid(
    row=currentRow * packCount, column=0
)
reset = Button(master, text="RESET", command=resetButton).grid(
    row=currentRow * packCount + 1, column=0
)

setValues()


master.mainloop()
