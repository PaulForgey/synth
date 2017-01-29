import math
import sys

class Table(object):
    def __init__(self, name, size):
        self.name = name
        self.size = size


    def encode(self, d):
        return d


class LogSinTable(Table):
    data = []

    def __init__(self):
        super(LogSinTable, self).__init__("Sine", "WORD")

        self.data.append((16 << 10)-1)
        for x in range(1,0x400):
            n = (float(x) / 1024.0)
            s = math.sin(n * math.pi / 2.0)
            l = math.log(s, 2.0)

            self.data.append(-int(round(l * 1024.0)))
        self.data.append(0)


    def encode(self, d):
        return d << 1


class ExpTable(Table):
    data = []

    def __init__(self):
        super(ExpTable, self).__init__("Exp", "WORD")

        for x in range(0,0x400):
            x = 0x3ff - x
            n = (float(x) / 1024.0)
            self.data.append(int(round((2 ** n) * 32768.0)))


class EGLogTable(Table):
    data = []

    def __init__(self):
        super(EGLogTable, self).__init__("EGLog", "WORD")

        self.data.append((16 << 10)-1)
        for x in range(1,0x400):
            n = int(round(math.log(float(x*64), 2.0) * 1024.0))
            n = 0x4000 - n
            self.data.append(n)
        self.data.append(0)


    def encode(self, d):
        return d << 1


class PitchTable(Table):
    data = []
    hi_c = 8372.018
    period = 4096

    def __init__(self):
        super(PitchTable, self).__init__("Pitch", "LONG")
        fs = 44.1e3
        base = self.period / fs * self.hi_c 

        for x in range(0,0x400):
            x = 0x3ff - x
            n = base * pow(2.0, float(x) / 1024.0)
            self.data.append(int(round(n * (1 << 20))))


class ScaleTable(Table):
    data = []

    def __init__(self):
        super(ScaleTable, self).__init__("Scale", "WORD")
        
        for x in range(0,12):
            n = int(round(1024.0 / 12.0 * x))
            self.data.append(n)


def print_table(t):
    print t.name
    i = iter(t.data)
    try:
        y = 0
        while True:
            for x in range(0, 0x20):
                if x == 0:
                    s = t.size
                elif x > 0:
                    s = ','
                sys.stdout.write("%s %s" % (s, t.encode(i.next())))
            sys.stdout.write(" ' %s\n" % hex(y))
            y += 0x20
    except StopIteration:
        print
    print


def test(env):
    t = LogSinTable()
    e = ExpTable()
    for x in range(0,0x1000):
        x &= 0xfff

        if x & 0x800:
            s = -1
        else:
            s = 1

        if x & 0x400:
            x = -x

        x &= 0x7ff

        yl = t.data[x]
        yl += env
        y = e.data[yl & 0x3ff] >> (yl >> 10)

        print y * s


def test_env():
    e = ExpTable()
    v = EGLogTable()
    for x in range(0,0x400):
        yl = v.data[x]
        y = e.data[yl & 0x3ff] >> (yl >> 10)

        print y


def tables():
    print "PUB SinePtr"
    print "    return @Sine"
    print
    print "PUB ExpPtr"
    print "    return @Exp"
    print
    print "PUB EGLogPtr"
    print "    return @EGLog"
    print
    print "PUB PitchPtr"
    print "    return @Pitch"
    print
    print "PUB ScalePtr"
    print "    return @Scale"
    print
    print "DAT"

    print_table(PitchTable())
    print_table(LogSinTable())
    print_table(ExpTable())
    print_table(EGLogTable())
    print_table(ScaleTable())


tables()
#test(2)
#test_env()
