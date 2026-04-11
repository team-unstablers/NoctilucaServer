//
//  Keycode.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation

public struct LinuxKeycode: RawRepresentable, Hashable, Equatable, Codable, Sendable {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let KEY_RESERVED = Self(rawValue: 0)
    public static let KEY_ESC = Self(rawValue: 1)
    public static let KEY_1 = Self(rawValue: 2)
    public static let KEY_2 = Self(rawValue: 3)
    public static let KEY_3 = Self(rawValue: 4)
    public static let KEY_4 = Self(rawValue: 5)
    public static let KEY_5 = Self(rawValue: 6)
    public static let KEY_6 = Self(rawValue: 7)
    public static let KEY_7 = Self(rawValue: 8)
    public static let KEY_8 = Self(rawValue: 9)
    public static let KEY_9 = Self(rawValue: 10)
    public static let KEY_0 = Self(rawValue: 11)
    public static let KEY_MINUS = Self(rawValue: 12)
    public static let KEY_EQUAL = Self(rawValue: 13)
    public static let KEY_BACKSPACE = Self(rawValue: 14)
    public static let KEY_TAB = Self(rawValue: 15)
    public static let KEY_Q = Self(rawValue: 16)
    public static let KEY_W = Self(rawValue: 17)
    public static let KEY_E = Self(rawValue: 18)
    public static let KEY_R = Self(rawValue: 19)
    public static let KEY_T = Self(rawValue: 20)
    public static let KEY_Y = Self(rawValue: 21)
    public static let KEY_U = Self(rawValue: 22)
    public static let KEY_I = Self(rawValue: 23)
    public static let KEY_O = Self(rawValue: 24)
    public static let KEY_P = Self(rawValue: 25)
    public static let KEY_LEFTBRACE = Self(rawValue: 26)
    public static let KEY_RIGHTBRACE = Self(rawValue: 27)
    public static let KEY_ENTER = Self(rawValue: 28)
    public static let KEY_LEFTCTRL = Self(rawValue: 29)
    public static let KEY_A = Self(rawValue: 30)
    public static let KEY_S = Self(rawValue: 31)
    public static let KEY_D = Self(rawValue: 32)
    public static let KEY_F = Self(rawValue: 33)
    public static let KEY_G = Self(rawValue: 34)
    public static let KEY_H = Self(rawValue: 35)
    public static let KEY_J = Self(rawValue: 36)
    public static let KEY_K = Self(rawValue: 37)
    public static let KEY_L = Self(rawValue: 38)
    public static let KEY_SEMICOLON = Self(rawValue: 39)
    public static let KEY_APOSTROPHE = Self(rawValue: 40)
    public static let KEY_GRAVE = Self(rawValue: 41)
    public static let KEY_LEFTSHIFT = Self(rawValue: 42)
    public static let KEY_BACKSLASH = Self(rawValue: 43)
    public static let KEY_Z = Self(rawValue: 44)
    public static let KEY_X = Self(rawValue: 45)
    public static let KEY_C = Self(rawValue: 46)
    public static let KEY_V = Self(rawValue: 47)
    public static let KEY_B = Self(rawValue: 48)
    public static let KEY_N = Self(rawValue: 49)
    public static let KEY_M = Self(rawValue: 50)
    public static let KEY_COMMA = Self(rawValue: 51)
    public static let KEY_DOT = Self(rawValue: 52)
    public static let KEY_SLASH = Self(rawValue: 53)
    public static let KEY_RIGHTSHIFT = Self(rawValue: 54)
    public static let KEY_KPASTERISK = Self(rawValue: 55)
    public static let KEY_LEFTALT = Self(rawValue: 56)
    public static let KEY_SPACE = Self(rawValue: 57)
    public static let KEY_CAPSLOCK = Self(rawValue: 58)
    public static let KEY_F1 = Self(rawValue: 59)
    public static let KEY_F2 = Self(rawValue: 60)
    public static let KEY_F3 = Self(rawValue: 61)
    public static let KEY_F4 = Self(rawValue: 62)
    public static let KEY_F5 = Self(rawValue: 63)
    public static let KEY_F6 = Self(rawValue: 64)
    public static let KEY_F7 = Self(rawValue: 65)
    public static let KEY_F8 = Self(rawValue: 66)
    public static let KEY_F9 = Self(rawValue: 67)
    public static let KEY_F10 = Self(rawValue: 68)
    public static let KEY_NUMLOCK = Self(rawValue: 69)
    public static let KEY_SCROLLLOCK = Self(rawValue: 70)
    public static let KEY_KP7 = Self(rawValue: 71)
    public static let KEY_KP8 = Self(rawValue: 72)
    public static let KEY_KP9 = Self(rawValue: 73)
    public static let KEY_KPMINUS = Self(rawValue: 74)
    public static let KEY_KP4 = Self(rawValue: 75)
    public static let KEY_KP5 = Self(rawValue: 76)
    public static let KEY_KP6 = Self(rawValue: 77)
    public static let KEY_KPPLUS = Self(rawValue: 78)
    public static let KEY_KP1 = Self(rawValue: 79)
    public static let KEY_KP2 = Self(rawValue: 80)
    public static let KEY_KP3 = Self(rawValue: 81)
    public static let KEY_KP0 = Self(rawValue: 82)
    public static let KEY_KPDOT = Self(rawValue: 83)

    public static let KEY_ZENKAKUHANKAKU = Self(rawValue: 85)
    public static let KEY_102ND = Self(rawValue: 86)
    public static let KEY_F11 = Self(rawValue: 87)
    public static let KEY_F12 = Self(rawValue: 88)
    public static let KEY_RO = Self(rawValue: 89)
    public static let KEY_KATAKANA = Self(rawValue: 90)
    public static let KEY_HIRAGANA = Self(rawValue: 91)
    public static let KEY_HENKAN = Self(rawValue: 92)
    public static let KEY_KATAKANAHIRAGANA = Self(rawValue: 93)
    public static let KEY_MUHENKAN = Self(rawValue: 94)
    public static let KEY_KPJPCOMMA = Self(rawValue: 95)
    public static let KEY_KPENTER = Self(rawValue: 96)
    public static let KEY_RIGHTCTRL = Self(rawValue: 97)
    public static let KEY_KPSLASH = Self(rawValue: 98)
    public static let KEY_SYSRQ = Self(rawValue: 99)
    public static let KEY_RIGHTALT = Self(rawValue: 100)
    public static let KEY_LINEFEED = Self(rawValue: 101)
    public static let KEY_HOME = Self(rawValue: 102)
    public static let KEY_UP = Self(rawValue: 103)
    public static let KEY_PAGEUP = Self(rawValue: 104)
    public static let KEY_LEFT = Self(rawValue: 105)
    public static let KEY_RIGHT = Self(rawValue: 106)
    public static let KEY_END = Self(rawValue: 107)
    public static let KEY_DOWN = Self(rawValue: 108)
    public static let KEY_PAGEDOWN = Self(rawValue: 109)
    public static let KEY_INSERT = Self(rawValue: 110)
    public static let KEY_DELETE = Self(rawValue: 111)
    public static let KEY_MACRO = Self(rawValue: 112)
    public static let KEY_MUTE = Self(rawValue: 113)
    public static let KEY_VOLUMEDOWN = Self(rawValue: 114)
    public static let KEY_VOLUMEUP = Self(rawValue: 115)
    public static let KEY_POWER = Self(rawValue: 116)    /* SC System Power Down */
    public static let KEY_KPEQUAL = Self(rawValue: 117)
    public static let KEY_KPPLUSMINUS = Self(rawValue: 118)
    public static let KEY_PAUSE = Self(rawValue: 119)
    public static let KEY_SCALE = Self(rawValue: 120)    /* AL Compiz Scale (Expose) */

    public static let KEY_KPCOMMA = Self(rawValue: 121)
    public static let KEY_HANGEUL = Self(rawValue: 122)
    public static let KEY_HANGUEL = Self.KEY_HANGEUL
    public static let KEY_HANJA = Self(rawValue: 123)
    public static let KEY_YEN = Self(rawValue: 124)
    public static let KEY_LEFTMETA = Self(rawValue: 125)
    public static let KEY_RIGHTMETA = Self(rawValue: 126)
    public static let KEY_COMPOSE = Self(rawValue: 127)

    public static let KEY_STOP = Self(rawValue: 128)    /* AC Stop */
    public static let KEY_AGAIN = Self(rawValue: 129)
    public static let KEY_PROPS = Self(rawValue: 130)    /* AC Properties */
    public static let KEY_UNDO = Self(rawValue: 131)    /* AC Undo */
    public static let KEY_FRONT = Self(rawValue: 132)
    public static let KEY_COPY = Self(rawValue: 133)    /* AC Copy */
    public static let KEY_OPEN = Self(rawValue: 134)    /* AC Open */
    public static let KEY_PASTE = Self(rawValue: 135)    /* AC Paste */
    public static let KEY_FIND = Self(rawValue: 136)    /* AC Search */
    public static let KEY_CUT = Self(rawValue: 137)    /* AC Cut */
    public static let KEY_HELP = Self(rawValue: 138)    /* AL Integrated Help Center */
    public static let KEY_MENU = Self(rawValue: 139)    /* Menu (show menu) */
    public static let KEY_CALC = Self(rawValue: 140)    /* AL Calculator */
    public static let KEY_SETUP = Self(rawValue: 141)
    public static let KEY_SLEEP = Self(rawValue: 142)    /* SC System Sleep */
    public static let KEY_WAKEUP = Self(rawValue: 143)    /* System Wake Up */
    public static let KEY_FILE = Self(rawValue: 144)    /* AL Local Machine Browser */
    public static let KEY_SENDFILE = Self(rawValue: 145)
    public static let KEY_DELETEFILE = Self(rawValue: 146)
    public static let KEY_XFER = Self(rawValue: 147)
    public static let KEY_PROG1 = Self(rawValue: 148)
    public static let KEY_PROG2 = Self(rawValue: 149)
    public static let KEY_WWW = Self(rawValue: 150)    /* AL Internet Browser */
    public static let KEY_MSDOS = Self(rawValue: 151)
    public static let KEY_COFFEE = Self(rawValue: 152)    /* AL Terminal Lock/Screensaver */
    public static let KEY_SCREENLOCK = Self.KEY_COFFEE
    public static let KEY_ROTATE_DISPLAY = Self(rawValue: 153)    /* Display orientation for e.g. tablets */
    public static let KEY_DIRECTION = Self.KEY_ROTATE_DISPLAY
    public static let KEY_CYCLEWINDOWS = Self(rawValue: 154)
    public static let KEY_MAIL = Self(rawValue: 155)
    public static let KEY_BOOKMARKS = Self(rawValue: 156)    /* AC Bookmarks */
    public static let KEY_COMPUTER = Self(rawValue: 157)
    public static let KEY_BACK = Self(rawValue: 158)    /* AC Back */
    public static let KEY_FORWARD = Self(rawValue: 159)    /* AC Forward */
    public static let KEY_CLOSECD = Self(rawValue: 160)
    public static let KEY_EJECTCD = Self(rawValue: 161)
    public static let KEY_EJECTCLOSECD = Self(rawValue: 162)
    public static let KEY_NEXTSONG = Self(rawValue: 163)
    public static let KEY_PLAYPAUSE = Self(rawValue: 164)
    public static let KEY_PREVIOUSSONG = Self(rawValue: 165)
    public static let KEY_STOPCD = Self(rawValue: 166)
    public static let KEY_RECORD = Self(rawValue: 167)
    public static let KEY_REWIND = Self(rawValue: 168)
    public static let KEY_PHONE = Self(rawValue: 169)    /* Media Select Telephone */
    public static let KEY_ISO = Self(rawValue: 170)
    public static let KEY_CONFIG = Self(rawValue: 171)    /* AL Consumer Control Configuration */
    public static let KEY_HOMEPAGE = Self(rawValue: 172)    /* AC Home */
    public static let KEY_REFRESH = Self(rawValue: 173)    /* AC Refresh */
    public static let KEY_EXIT = Self(rawValue: 174)    /* AC Exit */
    public static let KEY_MOVE = Self(rawValue: 175)
    public static let KEY_EDIT = Self(rawValue: 176)
    public static let KEY_SCROLLUP = Self(rawValue: 177)
    public static let KEY_SCROLLDOWN = Self(rawValue: 178)
    public static let KEY_KPLEFTPAREN = Self(rawValue: 179)
    public static let KEY_KPRIGHTPAREN = Self(rawValue: 180)
    public static let KEY_NEW = Self(rawValue: 181)    /* AC New */
    public static let KEY_REDO = Self(rawValue: 182)    /* AC Redo/Repeat */

    public static let KEY_F13 = Self(rawValue: 183)
    public static let KEY_F14 = Self(rawValue: 184)
    public static let KEY_F15 = Self(rawValue: 185)
    public static let KEY_F16 = Self(rawValue: 186)
    public static let KEY_F17 = Self(rawValue: 187)
    public static let KEY_F18 = Self(rawValue: 188)
    public static let KEY_F19 = Self(rawValue: 189)
    public static let KEY_F20 = Self(rawValue: 190)
    public static let KEY_F21 = Self(rawValue: 191)
    public static let KEY_F22 = Self(rawValue: 192)
    public static let KEY_F23 = Self(rawValue: 193)
    public static let KEY_F24 = Self(rawValue: 194)

    public static let KEY_PLAYCD = Self(rawValue: 200)
    public static let KEY_PAUSECD = Self(rawValue: 201)
    public static let KEY_PROG3 = Self(rawValue: 202)
    public static let KEY_PROG4 = Self(rawValue: 203)
    public static let KEY_ALL_APPLICATIONS = Self(rawValue: 204)    /* AC Desktop Show All Applications */
    public static let KEY_DASHBOARD = Self.KEY_ALL_APPLICATIONS
    public static let KEY_SUSPEND = Self(rawValue: 205)
    public static let KEY_CLOSE = Self(rawValue: 206)    /* AC Close */
    public static let KEY_PLAY = Self(rawValue: 207)
    public static let KEY_FASTFORWARD = Self(rawValue: 208)
    public static let KEY_BASSBOOST = Self(rawValue: 209)
    public static let KEY_PRINT = Self(rawValue: 210)    /* AC Print */
    public static let KEY_HP = Self(rawValue: 211)
    public static let KEY_CAMERA = Self(rawValue: 212)
    public static let KEY_SOUND = Self(rawValue: 213)
    public static let KEY_QUESTION = Self(rawValue: 214)
    public static let KEY_EMAIL = Self(rawValue: 215)
    public static let KEY_CHAT = Self(rawValue: 216)
    public static let KEY_SEARCH = Self(rawValue: 217)
    public static let KEY_CONNECT = Self(rawValue: 218)
    public static let KEY_FINANCE = Self(rawValue: 219)    /* AL Checkbook/Finance */
    public static let KEY_SPORT = Self(rawValue: 220)
    public static let KEY_SHOP = Self(rawValue: 221)
    public static let KEY_ALTERASE = Self(rawValue: 222)
    public static let KEY_CANCEL = Self(rawValue: 223)    /* AC Cancel */
    public static let KEY_BRIGHTNESSDOWN = Self(rawValue: 224)
    public static let KEY_BRIGHTNESSUP = Self(rawValue: 225)
    public static let KEY_MEDIA = Self(rawValue: 226)

    public static let KEY_SWITCHVIDEOMODE = Self(rawValue: 227)    /* Cycle between available video
                           outputs (Monitor/LCD/TV-out/etc) */
    public static let KEY_KBDILLUMTOGGLE = Self(rawValue: 228)
    public static let KEY_KBDILLUMDOWN = Self(rawValue: 229)
    public static let KEY_KBDILLUMUP = Self(rawValue: 230)

    public static let KEY_SEND = Self(rawValue: 231)    /* AC Send */
    public static let KEY_REPLY = Self(rawValue: 232)    /* AC Reply */
    public static let KEY_FORWARDMAIL = Self(rawValue: 233)    /* AC Forward Msg */
    public static let KEY_SAVE = Self(rawValue: 234)    /* AC Save */
    public static let KEY_DOCUMENTS = Self(rawValue: 235)

    public static let KEY_BATTERY = Self(rawValue: 236)

    public static let KEY_BLUETOOTH = Self(rawValue: 237)
    public static let KEY_WLAN = Self(rawValue: 238)
    public static let KEY_UWB = Self(rawValue: 239)

    public static let KEY_UNKNOWN = Self(rawValue: 240)

    public static let KEY_VIDEO_NEXT = Self(rawValue: 241)    /* drive next video source */
    public static let KEY_VIDEO_PREV = Self(rawValue: 242)    /* drive previous video source */
    public static let KEY_BRIGHTNESS_CYCLE = Self(rawValue: 243)    /* brightness up, after max is min */
    public static let KEY_BRIGHTNESS_AUTO = Self(rawValue: 244)    /* Set Auto Brightness: manual
                          brightness control is off,
                          rely on ambient */
    public static let KEY_BRIGHTNESS_ZERO = Self.KEY_BRIGHTNESS_AUTO
    public static let KEY_DISPLAY_OFF = Self(rawValue: 245)    /* display device to off state */

    public static let KEY_WWAN = Self(rawValue: 246)    /* Wireless WAN (LTE, UMTS, GSM, etc.) */
    public static let KEY_WIMAX = Self.KEY_WWAN
    public static let KEY_RFKILL = Self(rawValue: 247)    /* Key that controls all radios */

    public static let KEY_MICMUTE = Self(rawValue: 248)    /* Mute / unmute the microphone */
}
