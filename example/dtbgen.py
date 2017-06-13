#!/usr/bin/env python3

import argparse
import collections
import re
import sys
from xml.etree import ElementTree as ET
from pyfdt import pyfdt

STRICT_PARSING = True

parseables = []

def snakify(s):
    s1 = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', s)
    return re.sub('([a-z0-9])([A-Z])', r'\1_\2', s1).lower()

class ParseableMeta(type):
    def __new__(cls, name, bases, dict, register=True):
        if register:
            if dict.get('tag_name') is None:
                dict['tag_name'] = name
                if name[0].isupper():
                    dict['tag_name'] = name[0].lower() + name[1:]
            if dict.get('python_name') is None:
                dict['python_name'] = snakify(dict['tag_name'])
            if dict.get('python_plural') is None:
                dict['python_plural'] = dict['python_name'] + 's'
        else:
            dict['tag_name'] = None
            dict['python_name'] = None
            dict['python_plural'] = None

        P = super().__new__(cls, name, bases, dict)
        if register:
            parseables.append(P)
        return P

    def __init__(self, name, bases, dict, register=True):
        return super().__init__(name, bases, dict)

class Parseable(metaclass=ParseableMeta, register=False):
    tag_name = None
    python_name = None
    python_plural = None
    attrib_names = []
    object_names = []
    member_names = []
    defaults = {}
    types = {}
    
    def __init__(self, tree):
        res = dict(tree.attrib)
        for n in self.attrib_names:
            try:
                typ = self.types.get(n, lambda x: x)
                setattr(self, snakify(n), typ(res.pop(n)))
            except KeyError:
                if n in self.defaults:
                    setattr(self, snakify(n), self.defaults[n])
                else:
                    raise RuntimeError('required attribute for {}: {}'.format(self.tag_name, n))
        if STRICT_PARSING and res:
            raise RuntimeError('not used by {}: {}'.format(self.tag_name, res))

        for child in list(tree):
            if child.tag in self.member_names:
                tree.remove(child)

                if STRICT_PARSING and not len(child.attrib) == 0:
                    raise RuntimeError("unexpected attributes on struct member: {} {}".format(child.tag, child.attrib))
                typ = self.types.get(child.tag, lambda x: x)
                setattr(self, snakify(child.tag), typ(child.text))
        for n in self.member_names:
            if not snakify(n) in dir(self):
                if not n in self.defaults:
                    raise RuntimeError('required member for {}: {}'.format(self.tag_name, n))
                setattr(self, snakify(n), self.defaults[n])
        
        res = parse_tree(tree)
        for n in self.object_names:
            setattr(self, snakify(n), res.pop(n, []))
        if STRICT_PARSING and res:
            raise RuntimeError('not used by {}: {}'.format(self.tag_name, res))

    @classmethod
    def collect(cls, objs):
        return objs

    def __repr__(self):
        name = id(self)
        return '<{}: 0x{:x}>'.format(self.__class__.__name__, name)

class NamedParseable(Parseable, register=False):
    @classmethod
    def collect(cls, objs):
        collected = collections.OrderedDict()
        for o in objs:
            if o.name in collected:
                raise RuntimeError('non-unique name for {}: {}'.format(cls.tag_name, o.name))
            collected[o.name] = o
        return collected
    
    def __repr__(self):
        name = self.name
        return '<{}: {}>'.format(self.__class__.__name__, name)

def type_bool(b):
    if b.lower() in ['true', 't', '1']:
        return True
    elif b.lower() in ['false', 'f', '0']:
        return False
    else:
        raise ValueError('cannot parse boolean: {}'.format(b))

def type_int(i):
    return int(i, base=0)

class EnsembleReport(Parseable):
    tag_name = 'EnsembleReport'
    attrib_names = ['name', 'kind', 'fabric', 'version']
    member_names = ['reportVersion', 'uniqueIdentifier']
    object_names = ['parameters', 'modules', 'plugins', 'connections']

class Parameters(collections.UserDict):
    # http://docs.oracle.com/javase/7/docs/technotes/guides/jni/spec/types.html
    typemap = {
        'java.math.BigInteger': type_int,
        'java.lang.Integer': type_int,
        '[Ljava.lang.Integer;': str,
        'int': type_int,
        'java.lang.Long': type_int,
        'long': type_int,

        'double': float,
        
        'java.lang.String': str,
        '[Ljava.lang.String;': str,
        
        'java.lang.Boolean': type_bool,
        'boolean': type_bool,

        'com.altera.sopcmodel.reset.Reset$Edges': str,
        'com.altera.sopcmodel.interrupt.InterruptConnectionPoint$EIrqScheme': str,
        'com.altera.sopcmodel.avalon.AvalonConnectionPoint$AddressAlignment': str,
        'com.altera.sopcmodel.avalon.EAddrBurstUnits': str,
        'com.altera.sopcmodel.avalon.TimingUnits': str,
        'com.altera.entityinterfaces.IConnectionPoint': str,
    }
    
    def __init__(self):
        super().__init__()
        self.derived = {}
        self.enabled = {}
        self.visible = {}
        self.valid = {}
        self.sysinfo_type = {}
        self.sysinfo_arg = {}

    def add_parameter(self, p):
        if not p.type in self.typemap:
            raise RuntimeError('unknown parameter type {}'.format(p.type))
        if p.value is not None:
            self.data[p.name] = self.typemap[p.type](p.value)
        else:
            self.data[p.name] = None
        self.derived[p.name] = p.derived
        self.enabled[p.name] = p.enabled
        self.visible[p.name] = p.visible
        self.valid[p.name] = p.valid
        self.sysinfo_type[p.name] = p.sysinfo_type
        self.sysinfo_arg[p.name] = p.sysinfo_arg

class Parameter(Parseable):
    attrib_names = ['name']
    member_names = ['type', 'value', 'derived', 'enabled', 'visible', 'valid', 'sysinfo_type', 'sysinfo_arg']

    defaults = {
        'sysinfo_type': None,
        'sysinfo_arg': None,
    }

    @classmethod
    def collect(cls, vals):
        params = Parameters()
        for p in vals:
            params.add_parameter(p)
        return params

class Module(NamedParseable):
    attrib_names = ['kind', 'name', 'path', 'version']
    object_names = ['parameters', 'interfaces', 'assignments']

class Interface(NamedParseable):
    attrib_names = ['kind', 'name', 'version']
    object_names = ['parameters', 'ports', 'assignments', 'clock_domain_members', 'memory_blocks', 'interrupts']
    member_names = ['type', 'isStart']

class Connection(NamedParseable):
    attrib_names = ['end', 'kind', 'name', 'start', 'version']
    object_names = ['parameters']
    member_names = ['startModule', 'startConnectionPoint', 'endModule', 'endConnectionPoint']

class Plugin(Parseable):
    member_names = ['instanceCount', 'name', 'type', 'subtype', 'displayName', 'version']

class Assignment(Parseable):
    member_names = ['name', 'value']

    @classmethod
    def collect(cls, vals):
        collected = collections.OrderedDict()
        for v in vals:
            collected[v.name] = v.value
        return collected

class Port(NamedParseable):
    member_names = ['name', 'direction', 'width', 'role']

class ClockDomainMember(NamedParseable):
    member_names = ['isBridge', 'moduleName', 'slaveName', 'name']

class MemoryBlock(NamedParseable):
    member_names = ['isBridge', 'moduleName', 'slaveName', 'name', 'baseAddress', 'span']

    types = {
        'baseAddress': type_int,
        'span': type_int,
    }

class Interrupt(NamedParseable):
    member_names = ['isBridge', 'moduleName', 'slaveName', 'name', 'interruptNumber']

def parse_sopcinfo(f):
    tree = ET.parse(f)
    root = tree.getroot()

    is_valid = all(k in root.attrib for k in ['kind', 'name', 'fabric', 'version'])
    is_valid = is_valid and (root.tag == 'EnsembleReport')
    is_valid = is_valid and (root.attrib['kind'] == root.attrib['name'])
    is_valid = is_valid and (root.attrib['fabric'] == 'QSYS')
    is_valid = is_valid and (root.attrib['version'] == '1.0')
    if not is_valid:
        raise RuntimeError("this doesn't look like a sopcinfo file")

    return EnsembleReport(root)

def parse_tree(tree):
    ret = {}

    for child in tree:
        Objs = [O for O in parseables if O.tag_name == child.tag]
        if Objs:
            Obj = Objs[0]
            ret.setdefault(Obj.python_plural, []).append(Obj(child))
        elif STRICT_PARSING:
            ET.ElementTree(child).write(sys.stderr, encoding="unicode")
            raise RuntimeError("unknown tag: {} in {}".format(child.tag, tree.tag))

    collected = {}
    for k, v in ret.items():
        Obj = [O for O in parseables if k == O.python_plural][0]
        collected[k] = Obj.collect(v)

    return collected

def create_bridge(base, span, inner):
    bridge = pyfdt.FdtNode('bridge@0x{:x}'.format(base))
    bridge.append(pyfdt.FdtPropertyStrings('compatible', ['altr,bridge-1.0', 'simple-bus']))
    bridge.append(pyfdt.FdtPropertyWords('reg', [base, span]))
    # FIXME bridge.append(pyfdt.FdtPropertyWords('clocks', [2]))
    bridge.append(pyfdt.FdtPropertyWords('#address-cells', [2]))
    bridge.append(pyfdt.FdtPropertyWords('#size-cells', [1]))
    return {
        'node': bridge,
        'base': base,
        'inner': inner,
    }

bridges = {
    'h2f_lw_axi_master': create_bridge(0xff200000, 0x00200000, 0x1),
    'h2f_axi_master':    create_bridge(0xc0000000, 0x20000000, 0x0),
}

def param_to_node(name, v):
    try:
        v = int(v)
        return pyfdt.FdtPropertyWords(name, [v])
    except ValueError:
        raise RuntimeError("don't know how to convert dts param: {}".format(v))

def construct_sopc(info, hpsname):
    if not hpsname in info.modules:
        raise RuntimeError('cannot find Qsys module `{}`'.format(hpsname))
    hps = info.modules[hpsname]

    sopc = pyfdt.FdtNode('sopc')
    modules = collections.OrderedDict()

    for iface in hps.interfaces:
        if not iface in bridges:
            continue
        b = bridges[iface]
        ranges = []

        sopc.append(b['node'])
        for conn, blk in hps.interfaces[iface].memory_blocks.items():
            modname, port = conn.split('.', 1)
            modinfo = info.modules[modname]

            # FIXME compatible, versions
            vendor = modinfo.assignments.get('embeddedsw.dts.vendor')
            name = modinfo.assignments.get('embeddedsw.dts.name')
            group = modinfo.assignments.get('embeddedsw.dts.group')
            version = '1.0'

            if not all([vendor, name, group]):
                continue

            if not modname in modules:
                mod = {}
                modules[modname] = mod
                mod['name'] = '{}@0x{:x}'.format(group, (b['inner'] << 32) + blk.base_address)
                mod['compatible'] = pyfdt.FdtPropertyStrings('compatible', ['{},{}-{}'.format(vendor, name, version)])

                mod['reg'] = []
                mod['reg-names'] = []
                # FIXME interrupt-parent, interrupts
                # FIXME clocks, clock-names

                mod['params'] = []
                for k, v in modinfo.assignments.items():
                    if not k.startswith('embeddedsw.dts.params.'):
                        continue
                    k = k.split('.params.', 1)[1]
                    mod['params'].append(param_to_node(k, v))
            else:
                mod = modules[modname]

            ranges += [b['inner'], blk.base_address, b['base'] + blk.base_address, blk.span]
            mod['reg'] += [b['inner'], blk.base_address, blk.span]
            mod['reg-names'].append(port)
            
        b['node'].append(pyfdt.FdtPropertyWords('ranges', ranges))
        for mod in modules.values():
            node = pyfdt.FdtNode(mod['name'])
            node.append(mod['compatible'])
            node.append(pyfdt.FdtPropertyWords('reg', mod['reg']))
            node.append(pyfdt.FdtPropertyStrings('reg-names', mod['reg-names']))
            for m in mod['params']:
                node.append(m)
            b['node'].append(node)

    return sopc

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument('dtb', type=argparse.FileType('rb'))
    p.add_argument('sopcinfo', type=argparse.FileType('r'))
    p.add_argument('--hpsname', default='hps_0', help='name of the HPS module in Qsys (default: hps_0)')
    p.add_argument('-o', '--output', default='-', help='file to write to (default: stdout)')
    p.add_argument('-t', '--type', help='format to output (default: dts)', choices=['dts', 'dtb', 'json'], default='dts')
    p.add_argument('--only-new', action='store_true', default=False, help='only write new devices to output, do not patch')

    args = p.parse_args()

    fdt = pyfdt.FdtBlobParse(args.dtb).to_fdt()
    info = parse_sopcinfo(args.sopcinfo)

    sopc = None
    for node in fdt.rootnode:
        if not isinstance(node, pyfdt.FdtNode):
            continue
        try:
            i = node.index('device_type')
        except ValueError:
            continue
        attr = node[i]
        if 'soc' in attr:
            sopc = node
            break
    else:
        raise RuntimeError('failed to find SOC device in tree')

    newsopc = construct_sopc(info, args.hpsname)
    sopc.merge(newsopc)

    out = sys.stdout
    if args.type == 'dtb':
        out = sys.stdout.buffer
    
    if args.output != '-':
        mode = 'w'
        if args.type == 'dtb':
            mode = 'wb'
        out = open(args.output, mode)

    if args.only_new:
        fdt.add_rootnode(newsopc)
    
    with out:
        if args.type == 'dts':
            out.write(fdt.to_dts())
            out.write('\n')
        elif args.type == 'json':
            out.write(fdt.to_json())
            out.write('\n')
        elif args.type == 'dtb':
            out.write(fdt.to_dtb())
