using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace NvidiaVrrPatch {
    public class Connection {
        public string AdapterName;
        public string AdapterId;
        public string MonitorId;
        public string Description;
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DisplayDevice {
            public uint cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Description;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Key;
        }
        [DllImport("user32.dll", CharSet=CharSet.Unicode)]
        private static extern bool EnumDisplayDevicesW(string device, uint index, ref DisplayDevice output, uint flags);

        public static Connection[] Connections() {
            var result = new List<Connection>();
            for (uint i=0; i<64; i++) {
                var adapter = new DisplayDevice(); adapter.cb = (uint)Marshal.SizeOf(adapter);
                if (!EnumDisplayDevicesW(null, i, ref adapter, 0)) break;
                if ((adapter.Flags & 1)==0 || (adapter.Flags & 8)!=0) continue;
                if (adapter.Id==null || adapter.Id.IndexOf("VEN_10DE", StringComparison.OrdinalIgnoreCase)<0) continue;
                for (uint j=0; j<32; j++) {
                    var monitor = new DisplayDevice(); monitor.cb = (uint)Marshal.SizeOf(monitor);
                    if (!EnumDisplayDevicesW(adapter.Name, j, ref monitor, 1)) break;
                    if ((monitor.Flags & 1)==0 || monitor.Id==null) continue;
                    string id=monitor.Id;
                    if (id.StartsWith(@"\\?\")) id=id.Substring(4);
                    string[] parts=id.Split('#');
                    if (parts.Length<3 || !parts[0].Equals("DISPLAY", StringComparison.OrdinalIgnoreCase)) continue;
                    result.Add(new Connection { AdapterName=adapter.Name, AdapterId=adapter.Id,
                        MonitorId=parts[0]+@"\"+parts[1]+@"\"+parts[2], Description=adapter.Description });
                }
            }
            return result.ToArray();
        }
        public static byte[] BuildTable(string profile, string gpuFields, ushort manufacturerRaw,
                                        ushort product, string platformFields) {
            if (!BitConverter.IsLittleEndian) throw new InvalidOperationException("Little endian required.");
            if (!Regex.IsMatch(gpuFields ?? "", "^[0-9A-F]{16}$")) throw new ArgumentException("GPU IDs invalid.");
            // The template text below is the exact byte layout the driver's parser expects; it is
            // reproduced only so the generated table is readable by the driver (interoperability).
            // It is not a certification and does not imply any endorsement by NVIDIA.
            string template, fields;
            if (profile=="DellValidated") {
                if (!Regex.IsMatch(platformFields ?? "", "^[0-9A-F]{16}$")) throw new ArgumentException("Platform IDs invalid.");
                template="751115879849Genuine NVIDIA Certified GSync Ready Platform for "+
                    "XXXXXXXXXXXXXXXXXXXX - "+new string('Z',40)+
                    " - Copyright 2014 NVIDIA Corporation All Rights Reserved-589684029385(R)";
                fields=platformFields+gpuFields+manufacturerRaw.ToString("X4")+product.ToString("X4");
            } else if (profile=="Generic2023") {
                template="952000811869Genuine NVIDIA Certified GSync Ready Platform for "+
                    "XXXXXXXXXXXXXXXXXXXX - "+new string('Z',24)+
                    " - Copyright 2023 NVIDIA Corporation All Rights Reserved-972682349181(R)";
                fields=gpuFields+manufacturerRaw.ToString("X4")+product.ToString("X4");
            } else throw new ArgumentException("Unknown profile.");
            byte[] payload=Encoding.ASCII.GetBytes(template.Replace('X','0')+"\0");
            int checksum=0;
            for (int pos=62;pos<=81;pos++) checksum=(checksum+payload[pos])&255;
            int key=checksum%63, step=checksum/20;
            for (int i=0;i<fields.Length;i++) {
                int pos=85+i;
                payload[pos]=(byte)((((byte)fields[i]-32)^key)+32);
                key=(key+step)%63; step=(step+pos)&255;
            }
            var body=new List<byte>();
            body.AddRange(BitConverter.GetBytes((ushort)0x564b));
            body.AddRange(BitConverter.GetBytes((uint)(16+payload.Length)));
            body.AddRange(BitConverter.GetBytes((ushort)0x0100)); body.AddRange(payload);
            ulong hash=0xcbf29ce484222325;
            unchecked { foreach(byte value in body) hash=(hash^value)*0x100000001b3; }
            var obj=new List<byte>();obj.AddRange(BitConverter.GetBytes(hash));obj.AddRange(body);
            var table=new List<byte>();table.AddRange(BitConverter.GetBytes((uint)0x4e425349));
            table.AddRange(BitConverter.GetBytes((uint)(12+obj.Count)));
            table.Add(1);table.Add(1);table.AddRange(BitConverter.GetBytes((ushort)0x564b));table.AddRange(obj);
            return table.ToArray();
        }
    }
}
