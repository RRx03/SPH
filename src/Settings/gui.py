from tkinter import *
from json import *
from random import *


jsonDICO = {
    "SECURITY": 0,
    "RESET": 0,
    "RADIUS": 0.2,
    "H": 0.4,
    "TARGET_DENSITY": 1,
    "GAZ_CONSTANT": 1,
    "NEAR_GAZ_CONSTANT": 1,
    "VISCOSITY": 1,
}


settings = open("./src/Settings/settings.json", "w")
settings.write(dumps(jsonDICO))
settings.close()


def setValues():
    RADIUS.set(jsonDICO["RADIUS"])
    H.set(jsonDICO["H"])
    TARGET_DENSITY.set(jsonDICO["TARGET_DENSITY"])
    GAZ_CONSTANT.set(jsonDICO["GAZ_CONSTANT"])
    NEAR_GAZ_CONSTANT.set(jsonDICO["NEAR_GAZ_CONSTANT"])
    VISCOSITY.set(jsonDICO["VISCOSITY"])


def updateSettings(event):
    sendUpdates()
    return


def sendUpdates():
    jsonDICO["RADIUS"] = RADIUS.get()
    jsonDICO["H"] = H.get()
    jsonDICO["TARGET_DENSITY"] = TARGET_DENSITY.get()
    jsonDICO["GAZ_CONSTANT"] = GAZ_CONSTANT.get()
    jsonDICO["NEAR_GAZ_CONSTANT"] = NEAR_GAZ_CONSTANT.get()
    jsonDICO["VISCOSITY"] = VISCOSITY.get()
    jsonDICO["SECURITY"] = random()
    settings = open("./src/Settings/settings.json", "w")
    settings.write(dumps(jsonDICO))
    settings.close()


def resetButton():
    jsonDICO["RESET"] = 1 * (not jsonDICO["RESET"])
    sendUpdates()


master = Tk()
# choose the position of the window in the screen
master.geometry("+1000+0")
master.geometry("800x800")
master.title("GUI")
master.configure(bg="black")
currentRow = 2
master.grid_rowconfigure(currentRow - 1, minsize=20)
Label(master, text="RADIUS").grid(row=currentRow - 1, column=0)
RADIUS = DoubleVar()
radius = Scale(
    master,
    from_=0,
    to=2,
    length=800,
    orient=HORIZONTAL,
    resolution=0.01,
    command=updateSettings,
    variable=RADIUS,
).grid(row=currentRow, column=0)


currentRow = 4
master.grid_rowconfigure(currentRow - 1, minsize=20)
Label(master, text="H").grid(row=currentRow - 1, column=0)
H = DoubleVar()
h = Scale(
    master,
    from_=0.01,
    to=2,
    length=800,
    orient=HORIZONTAL,
    resolution=0.01,
    command=updateSettings,
    variable=H,
).grid(row=currentRow, column=0)


currentRow = 6
master.grid_rowconfigure(currentRow - 1, minsize=20)
Label(master, text="TARGET_DENSITY").grid(row=currentRow - 1, column=0)
TARGET_DENSITY = DoubleVar()
density = Scale(
    master,
    from_=0,
    to=1000,
    length=800,
    orient=HORIZONTAL,
    resolution=1,
    command=updateSettings,
    variable=TARGET_DENSITY,
).grid(row=currentRow, column=0)


currentRow = 8
master.grid_rowconfigure(currentRow - 1, minsize=20)
Label(master, text="GAZ_CONSTANT").grid(row=currentRow - 1, column=0)
GAZ_CONSTANT = DoubleVar()
gazC = Scale(
    master,
    from_=0,
    to=1000,
    length=800,
    orient=HORIZONTAL,
    resolution=1,
    command=updateSettings,
    variable=GAZ_CONSTANT,
).grid(row=currentRow, column=0)


currentRow = 10
master.grid_rowconfigure(currentRow - 1, minsize=20)
Label(master, text="NEAR_GAZ_CONSTANT").grid(row=currentRow - 1, column=0)
NEAR_GAZ_CONSTANT = DoubleVar()
gazNC = Scale(
    master,
    from_=0,
    to=1000,
    length=800,
    orient=HORIZONTAL,
    resolution=1,
    command=updateSettings,
    variable=NEAR_GAZ_CONSTANT,
).grid(row=currentRow, column=0)


currentRow = 12
master.grid_rowconfigure(currentRow - 1, minsize=20)
Label(master, text="VISCOSITY").grid(row=currentRow - 1, column=0)
VISCOSITY = DoubleVar()
visco = Scale(
    master,
    from_=0,
    to=10,
    length=800,
    orient=HORIZONTAL,
    resolution=0.01,
    command=updateSettings,
    variable=VISCOSITY,
).grid(row=currentRow, column=0)

currentRow = 14
master.grid_rowconfigure(currentRow - 1, minsize=20)
send = Button(master, text="SEND", command=sendUpdates).grid(row=currentRow, column=0)
currentRow = 16
master.grid_rowconfigure(currentRow - 1, minsize=20)
reset = Button(master, text="RESET", command=resetButton).grid(row=currentRow, column=0)

# Ajouter ENtry pour mettre direct la bonne valeur et une checkbox pour savoir si on auto update ou pas
setValues()


master.mainloop()
