// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// GENERATED FILE. Do not edit.
// Regenerate with: python3 scripts/gen_glyph_rom.py
// Source of truth for the bitmaps: scripts/font_data.py
//
// Dual bank glyph ROM, one 8 pixel row per word, most significant bit leftmost.
//
//   words    0 .. 2047   8x16 bank, index = code * 16 + row
//   words 2048 .. 3071   8x8  bank, index = 2048 + code * 8 + row
//
// Registered read port, one cycle latency, which is what lets the shader spend a
// whole clock on the lookup and lets the array map to a block RAM on an FPGA. The
// address is only rewritten once per character cell, so the output holds for the
// eight display pixels that follow without an extra register.

module vte_glyph_rom (
    input  logic                         clk_i,
    input  logic [vte_pkg::RomAddrW-1:0] addr_i,
    output logic [                  7:0] data_o
);

  logic [7:0] mem[0:vte_pkg::RomDepth-1];

  initial begin : p_rom_init
    for (int unsigned i = 0; i < vte_pkg::RomDepth; i++) mem[i] = 8'h00;
    // 8x16 bank
    // glyph 0x01
    mem[  16] = 8'h88; mem[  18] = 8'h22; mem[  20] = 8'h88; mem[  22] = 8'h22;
    mem[  24] = 8'h88; mem[  26] = 8'h22; mem[  28] = 8'h88; mem[  30] = 8'h22;
    // glyph 0x02
    mem[  32] = 8'hAA; mem[  33] = 8'h55; mem[  34] = 8'hAA; mem[  35] = 8'h55;
    mem[  36] = 8'hAA; mem[  37] = 8'h55; mem[  38] = 8'hAA; mem[  39] = 8'h55;
    mem[  40] = 8'hAA; mem[  41] = 8'h55; mem[  42] = 8'hAA; mem[  43] = 8'h55;
    mem[  44] = 8'hAA; mem[  45] = 8'h55; mem[  46] = 8'hAA; mem[  47] = 8'h55;
    // glyph 0x03
    mem[  48] = 8'h77; mem[  49] = 8'hFF; mem[  50] = 8'hDD; mem[  51] = 8'hFF;
    mem[  52] = 8'h77; mem[  53] = 8'hFF; mem[  54] = 8'hDD; mem[  55] = 8'hFF;
    mem[  56] = 8'h77; mem[  57] = 8'hFF; mem[  58] = 8'hDD; mem[  59] = 8'hFF;
    mem[  60] = 8'h77; mem[  61] = 8'hFF; mem[  62] = 8'hDD; mem[  63] = 8'hFF;
    // glyph 0x04
    mem[  64] = 8'hFF; mem[  65] = 8'hFF; mem[  66] = 8'hFF; mem[  67] = 8'hFF;
    mem[  68] = 8'hFF; mem[  69] = 8'hFF; mem[  70] = 8'hFF; mem[  71] = 8'hFF;
    mem[  72] = 8'hFF; mem[  73] = 8'hFF; mem[  74] = 8'hFF; mem[  75] = 8'hFF;
    mem[  76] = 8'hFF; mem[  77] = 8'hFF; mem[  78] = 8'hFF; mem[  79] = 8'hFF;
    // glyph 0x05
    mem[  80] = 8'hF0; mem[  81] = 8'hF0; mem[  82] = 8'hF0; mem[  83] = 8'hF0;
    mem[  84] = 8'hF0; mem[  85] = 8'hF0; mem[  86] = 8'hF0; mem[  87] = 8'hF0;
    mem[  88] = 8'hF0; mem[  89] = 8'hF0; mem[  90] = 8'hF0; mem[  91] = 8'hF0;
    mem[  92] = 8'hF0; mem[  93] = 8'hF0; mem[  94] = 8'hF0; mem[  95] = 8'hF0;
    // glyph 0x06
    mem[ 104] = 8'hFF; mem[ 105] = 8'hFF; mem[ 106] = 8'hFF; mem[ 107] = 8'hFF;
    mem[ 108] = 8'hFF; mem[ 109] = 8'hFF; mem[ 110] = 8'hFF; mem[ 111] = 8'hFF;
    // glyph 0x07
    mem[ 117] = 8'h3C; mem[ 118] = 8'h3C; mem[ 119] = 8'h3C; mem[ 120] = 8'h3C;
    // glyph 0x08
    mem[ 135] = 8'hFF; mem[ 136] = 8'hFF;
    // glyph 0x09
    mem[ 144] = 8'h18; mem[ 145] = 8'h18; mem[ 146] = 8'h18; mem[ 147] = 8'h18;
    mem[ 148] = 8'h18; mem[ 149] = 8'h18; mem[ 150] = 8'h18; mem[ 151] = 8'h18;
    mem[ 152] = 8'h18; mem[ 153] = 8'h18; mem[ 154] = 8'h18; mem[ 155] = 8'h18;
    mem[ 156] = 8'h18; mem[ 157] = 8'h18; mem[ 158] = 8'h18; mem[ 159] = 8'h18;
    // glyph 0x0A
    mem[ 167] = 8'h1F; mem[ 168] = 8'h1F; mem[ 169] = 8'h18; mem[ 170] = 8'h18;
    mem[ 171] = 8'h18; mem[ 172] = 8'h18; mem[ 173] = 8'h18; mem[ 174] = 8'h18;
    mem[ 175] = 8'h18;
    // glyph 0x0B
    mem[ 183] = 8'hF8; mem[ 184] = 8'hF8; mem[ 185] = 8'h18; mem[ 186] = 8'h18;
    mem[ 187] = 8'h18; mem[ 188] = 8'h18; mem[ 189] = 8'h18; mem[ 190] = 8'h18;
    mem[ 191] = 8'h18;
    // glyph 0x0C
    mem[ 192] = 8'h18; mem[ 193] = 8'h18; mem[ 194] = 8'h18; mem[ 195] = 8'h18;
    mem[ 196] = 8'h18; mem[ 197] = 8'h18; mem[ 198] = 8'h18; mem[ 199] = 8'h1F;
    mem[ 200] = 8'h1F;
    // glyph 0x0D
    mem[ 208] = 8'h18; mem[ 209] = 8'h18; mem[ 210] = 8'h18; mem[ 211] = 8'h18;
    mem[ 212] = 8'h18; mem[ 213] = 8'h18; mem[ 214] = 8'h18; mem[ 215] = 8'hF8;
    mem[ 216] = 8'hF8;
    // glyph 0x21 !
    mem[ 530] = 8'h30; mem[ 531] = 8'h30; mem[ 532] = 8'h30; mem[ 533] = 8'h30;
    mem[ 534] = 8'h30; mem[ 535] = 8'h30; mem[ 536] = 8'h30; mem[ 538] = 8'h30;
    mem[ 539] = 8'h30;
    // glyph 0x22 quote
    mem[ 546] = 8'h6C; mem[ 547] = 8'h6C; mem[ 548] = 8'h6C; mem[ 549] = 8'h48;
    // glyph 0x23 #
    mem[ 562] = 8'h24; mem[ 563] = 8'h24; mem[ 564] = 8'h6C; mem[ 565] = 8'hFE;
    mem[ 566] = 8'h6C; mem[ 567] = 8'h6C; mem[ 568] = 8'hFE; mem[ 569] = 8'h6C;
    mem[ 570] = 8'h24; mem[ 571] = 8'h24;
    // glyph 0x24 $
    mem[ 578] = 8'h18; mem[ 579] = 8'h3C; mem[ 580] = 8'h66; mem[ 581] = 8'h60;
    mem[ 582] = 8'h3C; mem[ 583] = 8'h0C; mem[ 584] = 8'h66; mem[ 585] = 8'h3C;
    mem[ 586] = 8'h18;
    // glyph 0x25 %
    mem[ 594] = 8'hC2; mem[ 595] = 8'hC6; mem[ 596] = 8'h0C; mem[ 597] = 8'h18;
    mem[ 598] = 8'h30; mem[ 599] = 8'h60; mem[ 600] = 8'hC6; mem[ 601] = 8'h86;
    // glyph 0x26 &
    mem[ 610] = 8'h38; mem[ 611] = 8'h6C; mem[ 612] = 8'h6C; mem[ 613] = 8'h38;
    mem[ 614] = 8'h78; mem[ 615] = 8'hD8; mem[ 616] = 8'hCC; mem[ 617] = 8'hCC;
    mem[ 618] = 8'h76;
    // glyph 0x27 apostrophe
    mem[ 626] = 8'h30; mem[ 627] = 8'h30; mem[ 628] = 8'h30; mem[ 629] = 8'h20;
    // glyph 0x28 (
    mem[ 642] = 8'h0C; mem[ 643] = 8'h18; mem[ 644] = 8'h30; mem[ 645] = 8'h30;
    mem[ 646] = 8'h30; mem[ 647] = 8'h30; mem[ 648] = 8'h30; mem[ 649] = 8'h30;
    mem[ 650] = 8'h18; mem[ 651] = 8'h0C;
    // glyph 0x29 )
    mem[ 658] = 8'h30; mem[ 659] = 8'h18; mem[ 660] = 8'h0C; mem[ 661] = 8'h0C;
    mem[ 662] = 8'h0C; mem[ 663] = 8'h0C; mem[ 664] = 8'h0C; mem[ 665] = 8'h0C;
    mem[ 666] = 8'h18; mem[ 667] = 8'h30;
    // glyph 0x2A *
    mem[ 676] = 8'h18; mem[ 677] = 8'hDB; mem[ 678] = 8'h7E; mem[ 679] = 8'h18;
    mem[ 680] = 8'h7E; mem[ 681] = 8'hDB; mem[ 682] = 8'h18;
    // glyph 0x2B +
    mem[ 692] = 8'h18; mem[ 693] = 8'h18; mem[ 694] = 8'h18; mem[ 695] = 8'hFE;
    mem[ 696] = 8'h18; mem[ 697] = 8'h18; mem[ 698] = 8'h18;
    // glyph 0x2C ,
    mem[ 714] = 8'h38; mem[ 715] = 8'h38; mem[ 716] = 8'h18; mem[ 717] = 8'h30;
    // glyph 0x2D -
    mem[ 727] = 8'hFC;
    // glyph 0x2E .
    mem[ 746] = 8'h38; mem[ 747] = 8'h38;
    // glyph 0x2F /
    mem[ 754] = 8'h0C; mem[ 755] = 8'h0C; mem[ 756] = 8'h18; mem[ 757] = 8'h18;
    mem[ 758] = 8'h30; mem[ 759] = 8'h30; mem[ 760] = 8'h60; mem[ 761] = 8'h60;
    mem[ 762] = 8'hC0; mem[ 763] = 8'hC0;
    // glyph 0x30 0
    mem[ 770] = 8'h3C; mem[ 771] = 8'h66; mem[ 772] = 8'h66; mem[ 773] = 8'h6E;
    mem[ 774] = 8'h6E; mem[ 775] = 8'h7E; mem[ 776] = 8'h76; mem[ 777] = 8'h66;
    mem[ 778] = 8'h3C;
    // glyph 0x31 1
    mem[ 786] = 8'h18; mem[ 787] = 8'h38; mem[ 788] = 8'h78; mem[ 789] = 8'h18;
    mem[ 790] = 8'h18; mem[ 791] = 8'h18; mem[ 792] = 8'h18; mem[ 793] = 8'h18;
    mem[ 794] = 8'h7E;
    // glyph 0x32 2
    mem[ 802] = 8'h3C; mem[ 803] = 8'h66; mem[ 804] = 8'h06; mem[ 805] = 8'h0C;
    mem[ 806] = 8'h18; mem[ 807] = 8'h30; mem[ 808] = 8'h60; mem[ 809] = 8'h66;
    mem[ 810] = 8'h7E;
    // glyph 0x33 3
    mem[ 818] = 8'h3C; mem[ 819] = 8'h66; mem[ 820] = 8'h06; mem[ 821] = 8'h1C;
    mem[ 822] = 8'h1C; mem[ 823] = 8'h06; mem[ 824] = 8'h06; mem[ 825] = 8'h66;
    mem[ 826] = 8'h3C;
    // glyph 0x34 4
    mem[ 834] = 8'h0E; mem[ 835] = 8'h1E; mem[ 836] = 8'h36; mem[ 837] = 8'h66;
    mem[ 838] = 8'hC6; mem[ 839] = 8'hFE; mem[ 840] = 8'h06; mem[ 841] = 8'h06;
    mem[ 842] = 8'h0F;
    // glyph 0x35 5
    mem[ 850] = 8'h7E; mem[ 851] = 8'h60; mem[ 852] = 8'h60; mem[ 853] = 8'h7C;
    mem[ 854] = 8'h06; mem[ 855] = 8'h06; mem[ 856] = 8'h06; mem[ 857] = 8'h66;
    mem[ 858] = 8'h3C;
    // glyph 0x36 6
    mem[ 866] = 8'h1C; mem[ 867] = 8'h30; mem[ 868] = 8'h60; mem[ 869] = 8'h7C;
    mem[ 870] = 8'h66; mem[ 871] = 8'h66; mem[ 872] = 8'h66; mem[ 873] = 8'h66;
    mem[ 874] = 8'h3C;
    // glyph 0x37 7
    mem[ 882] = 8'h7E; mem[ 883] = 8'h66; mem[ 884] = 8'h06; mem[ 885] = 8'h0C;
    mem[ 886] = 8'h18; mem[ 887] = 8'h18; mem[ 888] = 8'h18; mem[ 889] = 8'h18;
    mem[ 890] = 8'h18;
    // glyph 0x38 8
    mem[ 898] = 8'h3C; mem[ 899] = 8'h66; mem[ 900] = 8'h66; mem[ 901] = 8'h3C;
    mem[ 902] = 8'h66; mem[ 903] = 8'h66; mem[ 904] = 8'h66; mem[ 905] = 8'h66;
    mem[ 906] = 8'h3C;
    // glyph 0x39 9
    mem[ 914] = 8'h3C; mem[ 915] = 8'h66; mem[ 916] = 8'h66; mem[ 917] = 8'h66;
    mem[ 918] = 8'h3E; mem[ 919] = 8'h06; mem[ 920] = 8'h0C; mem[ 921] = 8'h18;
    mem[ 922] = 8'h38;
    // glyph 0x3A :
    mem[ 932] = 8'h38; mem[ 933] = 8'h38; mem[ 936] = 8'h38; mem[ 937] = 8'h38;
    // glyph 0x3B ;
    mem[ 948] = 8'h38; mem[ 949] = 8'h38; mem[ 952] = 8'h38; mem[ 953] = 8'h38;
    mem[ 954] = 8'h18; mem[ 955] = 8'h30;
    // glyph 0x3C <
    mem[ 963] = 8'h0E; mem[ 964] = 8'h18; mem[ 965] = 8'h30; mem[ 966] = 8'h60;
    mem[ 967] = 8'h30; mem[ 968] = 8'h18; mem[ 969] = 8'h0E;
    // glyph 0x3D =
    mem[ 981] = 8'hFE; mem[ 984] = 8'hFE;
    // glyph 0x3E >
    mem[ 995] = 8'hE0; mem[ 996] = 8'h18; mem[ 997] = 8'h0C; mem[ 998] = 8'h06;
    mem[ 999] = 8'h0C; mem[1000] = 8'h18; mem[1001] = 8'hE0;
    // glyph 0x3F ?
    mem[1010] = 8'h3C; mem[1011] = 8'h66; mem[1012] = 8'h06; mem[1013] = 8'h0C;
    mem[1014] = 8'h18; mem[1015] = 8'h18; mem[1017] = 8'h18; mem[1018] = 8'h18;
    // glyph 0x40 @
    mem[1026] = 8'h3C; mem[1027] = 8'h66; mem[1028] = 8'h66; mem[1029] = 8'h6E;
    mem[1030] = 8'h6E; mem[1031] = 8'h6E; mem[1032] = 8'h6C; mem[1033] = 8'h60;
    mem[1034] = 8'h3C;
    // glyph 0x41 A
    mem[1042] = 8'h18; mem[1043] = 8'h3C; mem[1044] = 8'h3C; mem[1045] = 8'h66;
    mem[1046] = 8'h66; mem[1047] = 8'hC3; mem[1048] = 8'hFF; mem[1049] = 8'hC3;
    mem[1050] = 8'hC3;
    // glyph 0x42 B
    mem[1058] = 8'hFC; mem[1059] = 8'h66; mem[1060] = 8'h66; mem[1061] = 8'h66;
    mem[1062] = 8'h7C; mem[1063] = 8'h66; mem[1064] = 8'h66; mem[1065] = 8'h66;
    mem[1066] = 8'hFC;
    // glyph 0x43 C
    mem[1074] = 8'h3E; mem[1075] = 8'h66; mem[1076] = 8'h60; mem[1077] = 8'h60;
    mem[1078] = 8'h60; mem[1079] = 8'h60; mem[1080] = 8'h60; mem[1081] = 8'h66;
    mem[1082] = 8'h3E;
    // glyph 0x44 D
    mem[1090] = 8'hFC; mem[1091] = 8'h66; mem[1092] = 8'h66; mem[1093] = 8'h66;
    mem[1094] = 8'h66; mem[1095] = 8'h66; mem[1096] = 8'h66; mem[1097] = 8'h66;
    mem[1098] = 8'hFC;
    // glyph 0x45 E
    mem[1106] = 8'h7E; mem[1107] = 8'h60; mem[1108] = 8'h60; mem[1109] = 8'h60;
    mem[1110] = 8'h7C; mem[1111] = 8'h60; mem[1112] = 8'h60; mem[1113] = 8'h60;
    mem[1114] = 8'h7E;
    // glyph 0x46 F
    mem[1122] = 8'h7E; mem[1123] = 8'h60; mem[1124] = 8'h60; mem[1125] = 8'h60;
    mem[1126] = 8'h7C; mem[1127] = 8'h60; mem[1128] = 8'h60; mem[1129] = 8'h60;
    mem[1130] = 8'h60;
    // glyph 0x47 G
    mem[1138] = 8'h3E; mem[1139] = 8'h66; mem[1140] = 8'h60; mem[1141] = 8'h60;
    mem[1142] = 8'h6E; mem[1143] = 8'h66; mem[1144] = 8'h66; mem[1145] = 8'h66;
    mem[1146] = 8'h3C;
    // glyph 0x48 H
    mem[1154] = 8'hC3; mem[1155] = 8'hC3; mem[1156] = 8'hC3; mem[1157] = 8'hC3;
    mem[1158] = 8'hFF; mem[1159] = 8'hC3; mem[1160] = 8'hC3; mem[1161] = 8'hC3;
    mem[1162] = 8'hC3;
    // glyph 0x49 I
    mem[1170] = 8'h7E; mem[1171] = 8'h18; mem[1172] = 8'h18; mem[1173] = 8'h18;
    mem[1174] = 8'h18; mem[1175] = 8'h18; mem[1176] = 8'h18; mem[1177] = 8'h18;
    mem[1178] = 8'h7E;
    // glyph 0x4A J
    mem[1186] = 8'h1E; mem[1187] = 8'h06; mem[1188] = 8'h06; mem[1189] = 8'h06;
    mem[1190] = 8'h06; mem[1191] = 8'h06; mem[1192] = 8'h66; mem[1193] = 8'h66;
    mem[1194] = 8'h3C;
    // glyph 0x4B K
    mem[1202] = 8'hC3; mem[1203] = 8'hC6; mem[1204] = 8'hCC; mem[1205] = 8'hD8;
    mem[1206] = 8'hF0; mem[1207] = 8'hD8; mem[1208] = 8'hCC; mem[1209] = 8'hC6;
    mem[1210] = 8'hC3;
    // glyph 0x4C L
    mem[1218] = 8'h60; mem[1219] = 8'h60; mem[1220] = 8'h60; mem[1221] = 8'h60;
    mem[1222] = 8'h60; mem[1223] = 8'h60; mem[1224] = 8'h60; mem[1225] = 8'h60;
    mem[1226] = 8'h7E;
    // glyph 0x4D M
    mem[1234] = 8'hC3; mem[1235] = 8'hE7; mem[1236] = 8'hFF; mem[1237] = 8'hDB;
    mem[1238] = 8'hDB; mem[1239] = 8'hC3; mem[1240] = 8'hC3; mem[1241] = 8'hC3;
    mem[1242] = 8'hC3;
    // glyph 0x4E N
    mem[1250] = 8'hC3; mem[1251] = 8'hE3; mem[1252] = 8'hF3; mem[1253] = 8'hDB;
    mem[1254] = 8'hCF; mem[1255] = 8'hC7; mem[1256] = 8'hC3; mem[1257] = 8'hC3;
    mem[1258] = 8'hC3;
    // glyph 0x4F O
    mem[1266] = 8'h3C; mem[1267] = 8'h66; mem[1268] = 8'hC3; mem[1269] = 8'hC3;
    mem[1270] = 8'hC3; mem[1271] = 8'hC3; mem[1272] = 8'hC3; mem[1273] = 8'h66;
    mem[1274] = 8'h3C;
    // glyph 0x50 P
    mem[1282] = 8'hFC; mem[1283] = 8'h66; mem[1284] = 8'h66; mem[1285] = 8'h66;
    mem[1286] = 8'h7C; mem[1287] = 8'h60; mem[1288] = 8'h60; mem[1289] = 8'h60;
    mem[1290] = 8'h60;
    // glyph 0x51 Q
    mem[1298] = 8'h3C; mem[1299] = 8'h66; mem[1300] = 8'hC3; mem[1301] = 8'hC3;
    mem[1302] = 8'hC3; mem[1303] = 8'hC3; mem[1304] = 8'hDB; mem[1305] = 8'h66;
    mem[1306] = 8'h3C; mem[1307] = 8'h0E;
    // glyph 0x52 R
    mem[1314] = 8'hFC; mem[1315] = 8'h66; mem[1316] = 8'h66; mem[1317] = 8'h66;
    mem[1318] = 8'h7C; mem[1319] = 8'h6C; mem[1320] = 8'h66; mem[1321] = 8'h66;
    mem[1322] = 8'h63;
    // glyph 0x53 S
    mem[1330] = 8'h3E; mem[1331] = 8'h66; mem[1332] = 8'h60; mem[1333] = 8'h30;
    mem[1334] = 8'h18; mem[1335] = 8'h0C; mem[1336] = 8'h06; mem[1337] = 8'h66;
    mem[1338] = 8'h7C;
    // glyph 0x54 T
    mem[1346] = 8'hFF; mem[1347] = 8'hDB; mem[1348] = 8'h18; mem[1349] = 8'h18;
    mem[1350] = 8'h18; mem[1351] = 8'h18; mem[1352] = 8'h18; mem[1353] = 8'h18;
    mem[1354] = 8'h3C;
    // glyph 0x55 U
    mem[1362] = 8'hC3; mem[1363] = 8'hC3; mem[1364] = 8'hC3; mem[1365] = 8'hC3;
    mem[1366] = 8'hC3; mem[1367] = 8'hC3; mem[1368] = 8'hC3; mem[1369] = 8'h66;
    mem[1370] = 8'h3C;
    // glyph 0x56 V
    mem[1378] = 8'hC3; mem[1379] = 8'hC3; mem[1380] = 8'hC3; mem[1381] = 8'hC3;
    mem[1382] = 8'hC3; mem[1383] = 8'h66; mem[1384] = 8'h66; mem[1385] = 8'h3C;
    mem[1386] = 8'h18;
    // glyph 0x57 W
    mem[1394] = 8'hC3; mem[1395] = 8'hC3; mem[1396] = 8'hC3; mem[1397] = 8'hDB;
    mem[1398] = 8'hDB; mem[1399] = 8'hDB; mem[1400] = 8'hFF; mem[1401] = 8'hE7;
    mem[1402] = 8'hC3;
    // glyph 0x58 X
    mem[1410] = 8'hC3; mem[1411] = 8'hC3; mem[1412] = 8'h66; mem[1413] = 8'h3C;
    mem[1414] = 8'h18; mem[1415] = 8'h3C; mem[1416] = 8'h66; mem[1417] = 8'hC3;
    mem[1418] = 8'hC3;
    // glyph 0x59 Y
    mem[1426] = 8'hC3; mem[1427] = 8'hC3; mem[1428] = 8'h66; mem[1429] = 8'h3C;
    mem[1430] = 8'h18; mem[1431] = 8'h18; mem[1432] = 8'h18; mem[1433] = 8'h18;
    mem[1434] = 8'h3C;
    // glyph 0x5A Z
    mem[1442] = 8'hFE; mem[1443] = 8'h06; mem[1444] = 8'h0C; mem[1445] = 8'h18;
    mem[1446] = 8'h30; mem[1447] = 8'h60; mem[1448] = 8'hC0; mem[1449] = 8'hC0;
    mem[1450] = 8'hFE;
    // glyph 0x5B [
    mem[1458] = 8'h3C; mem[1459] = 8'h30; mem[1460] = 8'h30; mem[1461] = 8'h30;
    mem[1462] = 8'h30; mem[1463] = 8'h30; mem[1464] = 8'h30; mem[1465] = 8'h30;
    mem[1466] = 8'h3C;
    // glyph 0x5C backslash
    mem[1474] = 8'hC0; mem[1475] = 8'hC0; mem[1476] = 8'h60; mem[1477] = 8'h60;
    mem[1478] = 8'h30; mem[1479] = 8'h30; mem[1480] = 8'h18; mem[1481] = 8'h18;
    mem[1482] = 8'h0C; mem[1483] = 8'h0C;
    // glyph 0x5D ]
    mem[1490] = 8'h3C; mem[1491] = 8'h0C; mem[1492] = 8'h0C; mem[1493] = 8'h0C;
    mem[1494] = 8'h0C; mem[1495] = 8'h0C; mem[1496] = 8'h0C; mem[1497] = 8'h0C;
    mem[1498] = 8'h3C;
    // glyph 0x5E ^
    mem[1506] = 8'h18; mem[1507] = 8'h3C; mem[1508] = 8'h66; mem[1509] = 8'hC3;
    // glyph 0x5F _
    mem[1533] = 8'hFF;
    // glyph 0x60 `
    mem[1538] = 8'h30; mem[1539] = 8'h18; mem[1540] = 8'h0C;
    // glyph 0x61 a
    mem[1557] = 8'h3C; mem[1558] = 8'h06; mem[1559] = 8'h3E; mem[1560] = 8'h66;
    mem[1561] = 8'h66; mem[1562] = 8'h3E;
    // glyph 0x62 b
    mem[1570] = 8'h60; mem[1571] = 8'h60; mem[1572] = 8'h60; mem[1573] = 8'h7C;
    mem[1574] = 8'h66; mem[1575] = 8'h66; mem[1576] = 8'h66; mem[1577] = 8'h66;
    mem[1578] = 8'h7C;
    // glyph 0x63 c
    mem[1589] = 8'h3E; mem[1590] = 8'h66; mem[1591] = 8'h60; mem[1592] = 8'h60;
    mem[1593] = 8'h66; mem[1594] = 8'h3E;
    // glyph 0x64 d
    mem[1602] = 8'h06; mem[1603] = 8'h06; mem[1604] = 8'h06; mem[1605] = 8'h3E;
    mem[1606] = 8'h66; mem[1607] = 8'h66; mem[1608] = 8'h66; mem[1609] = 8'h66;
    mem[1610] = 8'h3E;
    // glyph 0x65 e
    mem[1621] = 8'h3C; mem[1622] = 8'h66; mem[1623] = 8'h7E; mem[1624] = 8'h60;
    mem[1625] = 8'h66; mem[1626] = 8'h3C;
    // glyph 0x66 f
    mem[1634] = 8'h1E; mem[1635] = 8'h30; mem[1636] = 8'h30; mem[1637] = 8'h7E;
    mem[1638] = 8'h30; mem[1639] = 8'h30; mem[1640] = 8'h30; mem[1641] = 8'h30;
    mem[1642] = 8'h30;
    // glyph 0x67 g
    mem[1653] = 8'h3E; mem[1654] = 8'h66; mem[1655] = 8'h66; mem[1656] = 8'h66;
    mem[1657] = 8'h66; mem[1658] = 8'h3E; mem[1659] = 8'h06; mem[1660] = 8'h66;
    mem[1661] = 8'h3C;
    // glyph 0x68 h
    mem[1666] = 8'h60; mem[1667] = 8'h60; mem[1668] = 8'h60; mem[1669] = 8'h7C;
    mem[1670] = 8'h66; mem[1671] = 8'h66; mem[1672] = 8'h66; mem[1673] = 8'h66;
    mem[1674] = 8'h66;
    // glyph 0x69 i
    mem[1682] = 8'h18; mem[1683] = 8'h18; mem[1685] = 8'h38; mem[1686] = 8'h18;
    mem[1687] = 8'h18; mem[1688] = 8'h18; mem[1689] = 8'h18; mem[1690] = 8'h7E;
    // glyph 0x6A j
    mem[1698] = 8'h0C; mem[1699] = 8'h0C; mem[1701] = 8'h1C; mem[1702] = 8'h0C;
    mem[1703] = 8'h0C; mem[1704] = 8'h0C; mem[1705] = 8'h0C; mem[1706] = 8'h0C;
    mem[1707] = 8'h0C; mem[1708] = 8'h6C; mem[1709] = 8'h38;
    // glyph 0x6B k
    mem[1714] = 8'h60; mem[1715] = 8'h60; mem[1716] = 8'h60; mem[1717] = 8'h66;
    mem[1718] = 8'h6C; mem[1719] = 8'h78; mem[1720] = 8'h6C; mem[1721] = 8'h66;
    mem[1722] = 8'h63;
    // glyph 0x6C l
    mem[1730] = 8'h38; mem[1731] = 8'h18; mem[1732] = 8'h18; mem[1733] = 8'h18;
    mem[1734] = 8'h18; mem[1735] = 8'h18; mem[1736] = 8'h18; mem[1737] = 8'h18;
    mem[1738] = 8'h7E;
    // glyph 0x6D m
    mem[1749] = 8'hE6; mem[1750] = 8'hFF; mem[1751] = 8'hDB; mem[1752] = 8'hDB;
    mem[1753] = 8'hDB; mem[1754] = 8'hDB;
    // glyph 0x6E n
    mem[1765] = 8'h7C; mem[1766] = 8'h66; mem[1767] = 8'h66; mem[1768] = 8'h66;
    mem[1769] = 8'h66; mem[1770] = 8'h66;
    // glyph 0x6F o
    mem[1781] = 8'h3C; mem[1782] = 8'h66; mem[1783] = 8'h66; mem[1784] = 8'h66;
    mem[1785] = 8'h66; mem[1786] = 8'h3C;
    // glyph 0x70 p
    mem[1797] = 8'h7C; mem[1798] = 8'h66; mem[1799] = 8'h66; mem[1800] = 8'h66;
    mem[1801] = 8'h66; mem[1802] = 8'h7C; mem[1803] = 8'h60; mem[1804] = 8'h60;
    mem[1805] = 8'h60;
    // glyph 0x71 q
    mem[1813] = 8'h3E; mem[1814] = 8'h66; mem[1815] = 8'h66; mem[1816] = 8'h66;
    mem[1817] = 8'h66; mem[1818] = 8'h3E; mem[1819] = 8'h06; mem[1820] = 8'h06;
    mem[1821] = 8'h06;
    // glyph 0x72 r
    mem[1829] = 8'h6E; mem[1830] = 8'h72; mem[1831] = 8'h60; mem[1832] = 8'h60;
    mem[1833] = 8'h60; mem[1834] = 8'h60;
    // glyph 0x73 s
    mem[1845] = 8'h3E; mem[1846] = 8'h60; mem[1847] = 8'h3C; mem[1848] = 8'h06;
    mem[1849] = 8'h66; mem[1850] = 8'h7C;
    // glyph 0x74 t
    mem[1858] = 8'h30; mem[1859] = 8'h30; mem[1860] = 8'h30; mem[1861] = 8'h7E;
    mem[1862] = 8'h30; mem[1863] = 8'h30; mem[1864] = 8'h30; mem[1865] = 8'h36;
    mem[1866] = 8'h1C;
    // glyph 0x75 u
    mem[1877] = 8'h66; mem[1878] = 8'h66; mem[1879] = 8'h66; mem[1880] = 8'h66;
    mem[1881] = 8'h66; mem[1882] = 8'h3E;
    // glyph 0x76 v
    mem[1893] = 8'hC3; mem[1894] = 8'hC3; mem[1895] = 8'h66; mem[1896] = 8'h66;
    mem[1897] = 8'h3C; mem[1898] = 8'h18;
    // glyph 0x77 w
    mem[1909] = 8'hC3; mem[1910] = 8'hDB; mem[1911] = 8'hDB; mem[1912] = 8'hDB;
    mem[1913] = 8'hFF; mem[1914] = 8'h66;
    // glyph 0x78 x
    mem[1925] = 8'hC3; mem[1926] = 8'h66; mem[1927] = 8'h3C; mem[1928] = 8'h3C;
    mem[1929] = 8'h66; mem[1930] = 8'hC3;
    // glyph 0x79 y
    mem[1941] = 8'h66; mem[1942] = 8'h66; mem[1943] = 8'h66; mem[1944] = 8'h66;
    mem[1945] = 8'h66; mem[1946] = 8'h3E; mem[1947] = 8'h06; mem[1948] = 8'h66;
    mem[1949] = 8'h3C;
    // glyph 0x7A z
    mem[1957] = 8'h7E; mem[1958] = 8'h0C; mem[1959] = 8'h18; mem[1960] = 8'h30;
    mem[1961] = 8'h60; mem[1962] = 8'h7E;
    // glyph 0x7B {
    mem[1970] = 8'h0E; mem[1971] = 8'h18; mem[1972] = 8'h18; mem[1973] = 8'h18;
    mem[1974] = 8'h70; mem[1975] = 8'h18; mem[1976] = 8'h18; mem[1977] = 8'h18;
    mem[1978] = 8'h0E;
    // glyph 0x7C |
    mem[1986] = 8'h18; mem[1987] = 8'h18; mem[1988] = 8'h18; mem[1989] = 8'h18;
    mem[1990] = 8'h18; mem[1991] = 8'h18; mem[1992] = 8'h18; mem[1993] = 8'h18;
    mem[1994] = 8'h18; mem[1995] = 8'h18;
    // glyph 0x7D }
    mem[2002] = 8'h70; mem[2003] = 8'h18; mem[2004] = 8'h18; mem[2005] = 8'h18;
    mem[2006] = 8'h0E; mem[2007] = 8'h18; mem[2008] = 8'h18; mem[2009] = 8'h18;
    mem[2010] = 8'h70;
    // glyph 0x7E ~
    mem[2020] = 8'h3B; mem[2021] = 8'h6E;

    // 8x8 bank
    // glyph 0x01
    mem[2056] = 8'h88; mem[2058] = 8'h22; mem[2060] = 8'h88; mem[2062] = 8'h22;
    // glyph 0x02
    mem[2064] = 8'hAA; mem[2065] = 8'h55; mem[2066] = 8'hAA; mem[2067] = 8'h55;
    mem[2068] = 8'hAA; mem[2069] = 8'h55; mem[2070] = 8'hAA; mem[2071] = 8'h55;
    // glyph 0x03
    mem[2072] = 8'h77; mem[2073] = 8'hFF; mem[2074] = 8'hDD; mem[2075] = 8'hFF;
    mem[2076] = 8'h77; mem[2077] = 8'hFF; mem[2078] = 8'hDD; mem[2079] = 8'hFF;
    // glyph 0x04
    mem[2080] = 8'hFF; mem[2081] = 8'hFF; mem[2082] = 8'hFF; mem[2083] = 8'hFF;
    mem[2084] = 8'hFF; mem[2085] = 8'hFF; mem[2086] = 8'hFF; mem[2087] = 8'hFF;
    // glyph 0x05
    mem[2088] = 8'hF0; mem[2089] = 8'hF0; mem[2090] = 8'hF0; mem[2091] = 8'hF0;
    mem[2092] = 8'hF0; mem[2093] = 8'hF0; mem[2094] = 8'hF0; mem[2095] = 8'hF0;
    // glyph 0x06
    mem[2100] = 8'hFF; mem[2101] = 8'hFF; mem[2102] = 8'hFF; mem[2103] = 8'hFF;
    // glyph 0x07
    mem[2106] = 8'h38; mem[2107] = 8'h38; mem[2108] = 8'h38;
    // glyph 0x08
    mem[2115] = 8'hFF; mem[2116] = 8'hFF;
    // glyph 0x09
    mem[2120] = 8'h18; mem[2121] = 8'h18; mem[2122] = 8'h18; mem[2123] = 8'h18;
    mem[2124] = 8'h18; mem[2125] = 8'h18; mem[2126] = 8'h18; mem[2127] = 8'h18;
    // glyph 0x0A
    mem[2131] = 8'h1F; mem[2132] = 8'h1F; mem[2133] = 8'h18; mem[2134] = 8'h18;
    mem[2135] = 8'h18;
    // glyph 0x0B
    mem[2139] = 8'hF8; mem[2140] = 8'hF8; mem[2141] = 8'h18; mem[2142] = 8'h18;
    mem[2143] = 8'h18;
    // glyph 0x0C
    mem[2144] = 8'h18; mem[2145] = 8'h18; mem[2146] = 8'h18; mem[2147] = 8'h1F;
    mem[2148] = 8'h1F;
    // glyph 0x0D
    mem[2152] = 8'h18; mem[2153] = 8'h18; mem[2154] = 8'h18; mem[2155] = 8'hF8;
    mem[2156] = 8'hF8;
    // glyph 0x21 !
    mem[2312] = 8'h30; mem[2313] = 8'h30; mem[2314] = 8'h30; mem[2315] = 8'h30;
    mem[2316] = 8'h30; mem[2318] = 8'h30;
    // glyph 0x22 quote
    mem[2320] = 8'h6C; mem[2321] = 8'h6C;
    // glyph 0x23 #
    mem[2328] = 8'h6C; mem[2329] = 8'h6C; mem[2330] = 8'hFC; mem[2331] = 8'h6C;
    mem[2332] = 8'hFC; mem[2333] = 8'h6C; mem[2334] = 8'h6C;
    // glyph 0x24 $
    mem[2336] = 8'h30; mem[2337] = 8'h7C; mem[2338] = 8'hD8; mem[2339] = 8'h78;
    mem[2340] = 8'h1C; mem[2341] = 8'hF8; mem[2342] = 8'h30;
    // glyph 0x25 %
    mem[2344] = 8'hC4; mem[2345] = 8'hCC; mem[2346] = 8'h18; mem[2347] = 8'h30;
    mem[2348] = 8'h60; mem[2349] = 8'hCC; mem[2350] = 8'h8C;
    // glyph 0x26 &
    mem[2352] = 8'h70; mem[2353] = 8'hD8; mem[2354] = 8'h70; mem[2355] = 8'hF0;
    mem[2356] = 8'hDC; mem[2357] = 8'hCC; mem[2358] = 8'h7C;
    // glyph 0x27 apostrophe
    mem[2360] = 8'h30; mem[2361] = 8'h30;
    // glyph 0x28 (
    mem[2368] = 8'h18; mem[2369] = 8'h30; mem[2370] = 8'h60; mem[2371] = 8'h60;
    mem[2372] = 8'h60; mem[2373] = 8'h30; mem[2374] = 8'h18;
    // glyph 0x29 )
    mem[2376] = 8'h60; mem[2377] = 8'h30; mem[2378] = 8'h18; mem[2379] = 8'h18;
    mem[2380] = 8'h18; mem[2381] = 8'h30; mem[2382] = 8'h60;
    // glyph 0x2A *
    mem[2385] = 8'hCC; mem[2386] = 8'h78; mem[2387] = 8'hFC; mem[2388] = 8'h78;
    mem[2389] = 8'hCC;
    // glyph 0x2B +
    mem[2393] = 8'h30; mem[2394] = 8'h30; mem[2395] = 8'hFC; mem[2396] = 8'h30;
    mem[2397] = 8'h30;
    // glyph 0x2C ,
    mem[2405] = 8'h30; mem[2406] = 8'h30; mem[2407] = 8'h60;
    // glyph 0x2D -
    mem[2411] = 8'hFC;
    // glyph 0x2E .
    mem[2421] = 8'h30; mem[2422] = 8'h30;
    // glyph 0x2F /
    mem[2424] = 8'h0C; mem[2425] = 8'h0C; mem[2426] = 8'h18; mem[2427] = 8'h30;
    mem[2428] = 8'h60; mem[2429] = 8'hC0; mem[2430] = 8'hC0;
    // glyph 0x30 0
    mem[2432] = 8'h78; mem[2433] = 8'hCC; mem[2434] = 8'hDC; mem[2435] = 8'hFC;
    mem[2436] = 8'hEC; mem[2437] = 8'hCC; mem[2438] = 8'h78;
    // glyph 0x31 1
    mem[2440] = 8'h30; mem[2441] = 8'h70; mem[2442] = 8'h30; mem[2443] = 8'h30;
    mem[2444] = 8'h30; mem[2445] = 8'h30; mem[2446] = 8'hFC;
    // glyph 0x32 2
    mem[2448] = 8'h78; mem[2449] = 8'hCC; mem[2450] = 8'h0C; mem[2451] = 8'h38;
    mem[2452] = 8'h60; mem[2453] = 8'hCC; mem[2454] = 8'hFC;
    // glyph 0x33 3
    mem[2456] = 8'hFC; mem[2457] = 8'h0C; mem[2458] = 8'h18; mem[2459] = 8'h38;
    mem[2460] = 8'h0C; mem[2461] = 8'hCC; mem[2462] = 8'h78;
    // glyph 0x34 4
    mem[2464] = 8'h1C; mem[2465] = 8'h3C; mem[2466] = 8'h6C; mem[2467] = 8'hCC;
    mem[2468] = 8'hFC; mem[2469] = 8'h0C; mem[2470] = 8'h0C;
    // glyph 0x35 5
    mem[2472] = 8'hFC; mem[2473] = 8'hC0; mem[2474] = 8'hF8; mem[2475] = 8'h0C;
    mem[2476] = 8'h0C; mem[2477] = 8'hCC; mem[2478] = 8'h78;
    // glyph 0x36 6
    mem[2480] = 8'h38; mem[2481] = 8'h60; mem[2482] = 8'hC0; mem[2483] = 8'hF8;
    mem[2484] = 8'hCC; mem[2485] = 8'hCC; mem[2486] = 8'h78;
    // glyph 0x37 7
    mem[2488] = 8'hFC; mem[2489] = 8'hCC; mem[2490] = 8'h0C; mem[2491] = 8'h18;
    mem[2492] = 8'h30; mem[2493] = 8'h30; mem[2494] = 8'h30;
    // glyph 0x38 8
    mem[2496] = 8'h78; mem[2497] = 8'hCC; mem[2498] = 8'hCC; mem[2499] = 8'h78;
    mem[2500] = 8'hCC; mem[2501] = 8'hCC; mem[2502] = 8'h78;
    // glyph 0x39 9
    mem[2504] = 8'h78; mem[2505] = 8'hCC; mem[2506] = 8'hCC; mem[2507] = 8'h7C;
    mem[2508] = 8'h0C; mem[2509] = 8'h18; mem[2510] = 8'h70;
    // glyph 0x3A :
    mem[2513] = 8'h30; mem[2514] = 8'h30; mem[2516] = 8'h30; mem[2517] = 8'h30;
    // glyph 0x3B ;
    mem[2521] = 8'h30; mem[2522] = 8'h30; mem[2524] = 8'h30; mem[2525] = 8'h30;
    mem[2526] = 8'h60;
    // glyph 0x3C <
    mem[2528] = 8'h0C; mem[2529] = 8'h18; mem[2530] = 8'h30; mem[2531] = 8'h60;
    mem[2532] = 8'h30; mem[2533] = 8'h18; mem[2534] = 8'h0C;
    // glyph 0x3D =
    mem[2538] = 8'hFC; mem[2540] = 8'hFC;
    // glyph 0x3E >
    mem[2544] = 8'h60; mem[2545] = 8'h30; mem[2546] = 8'h18; mem[2547] = 8'h0C;
    mem[2548] = 8'h18; mem[2549] = 8'h30; mem[2550] = 8'h60;
    // glyph 0x3F ?
    mem[2552] = 8'h78; mem[2553] = 8'hCC; mem[2554] = 8'h0C; mem[2555] = 8'h18;
    mem[2556] = 8'h18; mem[2558] = 8'h18;
    // glyph 0x40 @
    mem[2560] = 8'h78; mem[2561] = 8'hCC; mem[2562] = 8'hDC; mem[2563] = 8'hDC;
    mem[2564] = 8'hDC; mem[2565] = 8'hC0; mem[2566] = 8'h78;
    // glyph 0x41 A
    mem[2568] = 8'h30; mem[2569] = 8'h78; mem[2570] = 8'hCC; mem[2571] = 8'hCC;
    mem[2572] = 8'hFC; mem[2573] = 8'hCC; mem[2574] = 8'hCC;
    // glyph 0x42 B
    mem[2576] = 8'hF8; mem[2577] = 8'hCC; mem[2578] = 8'hCC; mem[2579] = 8'hF8;
    mem[2580] = 8'hCC; mem[2581] = 8'hCC; mem[2582] = 8'hF8;
    // glyph 0x43 C
    mem[2584] = 8'h78; mem[2585] = 8'hCC; mem[2586] = 8'hC0; mem[2587] = 8'hC0;
    mem[2588] = 8'hC0; mem[2589] = 8'hCC; mem[2590] = 8'h78;
    // glyph 0x44 D
    mem[2592] = 8'hF8; mem[2593] = 8'hCC; mem[2594] = 8'hCC; mem[2595] = 8'hCC;
    mem[2596] = 8'hCC; mem[2597] = 8'hCC; mem[2598] = 8'hF8;
    // glyph 0x45 E
    mem[2600] = 8'hFC; mem[2601] = 8'hC0; mem[2602] = 8'hC0; mem[2603] = 8'hF8;
    mem[2604] = 8'hC0; mem[2605] = 8'hC0; mem[2606] = 8'hFC;
    // glyph 0x46 F
    mem[2608] = 8'hFC; mem[2609] = 8'hC0; mem[2610] = 8'hC0; mem[2611] = 8'hF8;
    mem[2612] = 8'hC0; mem[2613] = 8'hC0; mem[2614] = 8'hC0;
    // glyph 0x47 G
    mem[2616] = 8'h78; mem[2617] = 8'hCC; mem[2618] = 8'hC0; mem[2619] = 8'hDC;
    mem[2620] = 8'hCC; mem[2621] = 8'hCC; mem[2622] = 8'h78;
    // glyph 0x48 H
    mem[2624] = 8'hCC; mem[2625] = 8'hCC; mem[2626] = 8'hCC; mem[2627] = 8'hFC;
    mem[2628] = 8'hCC; mem[2629] = 8'hCC; mem[2630] = 8'hCC;
    // glyph 0x49 I
    mem[2632] = 8'hFC; mem[2633] = 8'h30; mem[2634] = 8'h30; mem[2635] = 8'h30;
    mem[2636] = 8'h30; mem[2637] = 8'h30; mem[2638] = 8'hFC;
    // glyph 0x4A J
    mem[2640] = 8'h3C; mem[2641] = 8'h18; mem[2642] = 8'h18; mem[2643] = 8'h18;
    mem[2644] = 8'h18; mem[2645] = 8'hD8; mem[2646] = 8'h70;
    // glyph 0x4B K
    mem[2648] = 8'hCC; mem[2649] = 8'hCC; mem[2650] = 8'hD8; mem[2651] = 8'hF0;
    mem[2652] = 8'hD8; mem[2653] = 8'hCC; mem[2654] = 8'hCC;
    // glyph 0x4C L
    mem[2656] = 8'hC0; mem[2657] = 8'hC0; mem[2658] = 8'hC0; mem[2659] = 8'hC0;
    mem[2660] = 8'hC0; mem[2661] = 8'hC0; mem[2662] = 8'hFC;
    // glyph 0x4D M
    mem[2664] = 8'hC6; mem[2665] = 8'hEE; mem[2666] = 8'hFE; mem[2667] = 8'hD6;
    mem[2668] = 8'hC6; mem[2669] = 8'hC6; mem[2670] = 8'hC6;
    // glyph 0x4E N
    mem[2672] = 8'hCC; mem[2673] = 8'hEC; mem[2674] = 8'hFC; mem[2675] = 8'hFC;
    mem[2676] = 8'hDC; mem[2677] = 8'hCC; mem[2678] = 8'hCC;
    // glyph 0x4F O
    mem[2680] = 8'h78; mem[2681] = 8'hCC; mem[2682] = 8'hCC; mem[2683] = 8'hCC;
    mem[2684] = 8'hCC; mem[2685] = 8'hCC; mem[2686] = 8'h78;
    // glyph 0x50 P
    mem[2688] = 8'hF8; mem[2689] = 8'hCC; mem[2690] = 8'hCC; mem[2691] = 8'hF8;
    mem[2692] = 8'hC0; mem[2693] = 8'hC0; mem[2694] = 8'hC0;
    // glyph 0x51 Q
    mem[2696] = 8'h78; mem[2697] = 8'hCC; mem[2698] = 8'hCC; mem[2699] = 8'hCC;
    mem[2700] = 8'hDC; mem[2701] = 8'h78; mem[2702] = 8'h1C;
    // glyph 0x52 R
    mem[2704] = 8'hF8; mem[2705] = 8'hCC; mem[2706] = 8'hCC; mem[2707] = 8'hF8;
    mem[2708] = 8'hD8; mem[2709] = 8'hCC; mem[2710] = 8'hCC;
    // glyph 0x53 S
    mem[2712] = 8'h78; mem[2713] = 8'hCC; mem[2714] = 8'hC0; mem[2715] = 8'h78;
    mem[2716] = 8'h0C; mem[2717] = 8'hCC; mem[2718] = 8'h78;
    // glyph 0x54 T
    mem[2720] = 8'hFC; mem[2721] = 8'h30; mem[2722] = 8'h30; mem[2723] = 8'h30;
    mem[2724] = 8'h30; mem[2725] = 8'h30; mem[2726] = 8'h30;
    // glyph 0x55 U
    mem[2728] = 8'hCC; mem[2729] = 8'hCC; mem[2730] = 8'hCC; mem[2731] = 8'hCC;
    mem[2732] = 8'hCC; mem[2733] = 8'hCC; mem[2734] = 8'h78;
    // glyph 0x56 V
    mem[2736] = 8'hCC; mem[2737] = 8'hCC; mem[2738] = 8'hCC; mem[2739] = 8'hCC;
    mem[2740] = 8'hCC; mem[2741] = 8'h78; mem[2742] = 8'h30;
    // glyph 0x57 W
    mem[2744] = 8'hC6; mem[2745] = 8'hC6; mem[2746] = 8'hC6; mem[2747] = 8'hD6;
    mem[2748] = 8'hFE; mem[2749] = 8'hEE; mem[2750] = 8'hC6;
    // glyph 0x58 X
    mem[2752] = 8'hCC; mem[2753] = 8'hCC; mem[2754] = 8'h78; mem[2755] = 8'h30;
    mem[2756] = 8'h78; mem[2757] = 8'hCC; mem[2758] = 8'hCC;
    // glyph 0x59 Y
    mem[2760] = 8'hCC; mem[2761] = 8'hCC; mem[2762] = 8'hCC; mem[2763] = 8'h78;
    mem[2764] = 8'h30; mem[2765] = 8'h30; mem[2766] = 8'h30;
    // glyph 0x5A Z
    mem[2768] = 8'hFC; mem[2769] = 8'h0C; mem[2770] = 8'h18; mem[2771] = 8'h30;
    mem[2772] = 8'h60; mem[2773] = 8'hC0; mem[2774] = 8'hFC;
    // glyph 0x5B [
    mem[2776] = 8'h78; mem[2777] = 8'h60; mem[2778] = 8'h60; mem[2779] = 8'h60;
    mem[2780] = 8'h60; mem[2781] = 8'h60; mem[2782] = 8'h78;
    // glyph 0x5C backslash
    mem[2784] = 8'hC0; mem[2785] = 8'hC0; mem[2786] = 8'h60; mem[2787] = 8'h30;
    mem[2788] = 8'h18; mem[2789] = 8'h0C; mem[2790] = 8'h0C;
    // glyph 0x5D ]
    mem[2792] = 8'h78; mem[2793] = 8'h18; mem[2794] = 8'h18; mem[2795] = 8'h18;
    mem[2796] = 8'h18; mem[2797] = 8'h18; mem[2798] = 8'h78;
    // glyph 0x5E ^
    mem[2800] = 8'h30; mem[2801] = 8'h78; mem[2802] = 8'hCC;
    // glyph 0x5F _
    mem[2815] = 8'hFC;
    // glyph 0x60 `
    mem[2816] = 8'h60; mem[2817] = 8'h30;
    // glyph 0x61 a
    mem[2826] = 8'h78; mem[2827] = 8'h0C; mem[2828] = 8'h7C; mem[2829] = 8'hCC;
    mem[2830] = 8'h7C;
    // glyph 0x62 b
    mem[2832] = 8'hC0; mem[2833] = 8'hC0; mem[2834] = 8'hF8; mem[2835] = 8'hCC;
    mem[2836] = 8'hCC; mem[2837] = 8'hCC; mem[2838] = 8'hF8;
    // glyph 0x63 c
    mem[2842] = 8'h78; mem[2843] = 8'hCC; mem[2844] = 8'hC0; mem[2845] = 8'hCC;
    mem[2846] = 8'h78;
    // glyph 0x64 d
    mem[2848] = 8'h0C; mem[2849] = 8'h0C; mem[2850] = 8'h7C; mem[2851] = 8'hCC;
    mem[2852] = 8'hCC; mem[2853] = 8'hCC; mem[2854] = 8'h7C;
    // glyph 0x65 e
    mem[2858] = 8'h78; mem[2859] = 8'hCC; mem[2860] = 8'hFC; mem[2861] = 8'hC0;
    mem[2862] = 8'h78;
    // glyph 0x66 f
    mem[2864] = 8'h38; mem[2865] = 8'h60; mem[2866] = 8'hF8; mem[2867] = 8'h60;
    mem[2868] = 8'h60; mem[2869] = 8'h60; mem[2870] = 8'h60;
    // glyph 0x67 g
    mem[2874] = 8'h7C; mem[2875] = 8'hCC; mem[2876] = 8'hCC; mem[2877] = 8'h7C;
    mem[2878] = 8'h0C; mem[2879] = 8'h78;
    // glyph 0x68 h
    mem[2880] = 8'hC0; mem[2881] = 8'hC0; mem[2882] = 8'hF8; mem[2883] = 8'hCC;
    mem[2884] = 8'hCC; mem[2885] = 8'hCC; mem[2886] = 8'hCC;
    // glyph 0x69 i
    mem[2888] = 8'h30; mem[2890] = 8'h30; mem[2891] = 8'h30; mem[2892] = 8'h30;
    mem[2893] = 8'h30; mem[2894] = 8'h30;
    // glyph 0x6A j
    mem[2896] = 8'h18; mem[2898] = 8'h18; mem[2899] = 8'h18; mem[2900] = 8'h18;
    mem[2901] = 8'h18; mem[2902] = 8'hD8; mem[2903] = 8'h70;
    // glyph 0x6B k
    mem[2904] = 8'hC0; mem[2905] = 8'hC0; mem[2906] = 8'hCC; mem[2907] = 8'hD8;
    mem[2908] = 8'hF0; mem[2909] = 8'hD8; mem[2910] = 8'hCC;
    // glyph 0x6C l
    mem[2912] = 8'h60; mem[2913] = 8'h60; mem[2914] = 8'h60; mem[2915] = 8'h60;
    mem[2916] = 8'h60; mem[2917] = 8'h60; mem[2918] = 8'h38;
    // glyph 0x6D m
    mem[2922] = 8'hEC; mem[2923] = 8'hFE; mem[2924] = 8'hD6; mem[2925] = 8'hD6;
    mem[2926] = 8'hD6;
    // glyph 0x6E n
    mem[2930] = 8'hF8; mem[2931] = 8'hCC; mem[2932] = 8'hCC; mem[2933] = 8'hCC;
    mem[2934] = 8'hCC;
    // glyph 0x6F o
    mem[2938] = 8'h78; mem[2939] = 8'hCC; mem[2940] = 8'hCC; mem[2941] = 8'hCC;
    mem[2942] = 8'h78;
    // glyph 0x70 p
    mem[2946] = 8'hF8; mem[2947] = 8'hCC; mem[2948] = 8'hCC; mem[2949] = 8'hCC;
    mem[2950] = 8'hF8; mem[2951] = 8'hC0;
    // glyph 0x71 q
    mem[2954] = 8'h7C; mem[2955] = 8'hCC; mem[2956] = 8'hCC; mem[2957] = 8'hCC;
    mem[2958] = 8'h7C; mem[2959] = 8'h0C;
    // glyph 0x72 r
    mem[2962] = 8'hDC; mem[2963] = 8'hE0; mem[2964] = 8'hC0; mem[2965] = 8'hC0;
    mem[2966] = 8'hC0;
    // glyph 0x73 s
    mem[2970] = 8'h7C; mem[2971] = 8'hC0; mem[2972] = 8'h78; mem[2973] = 8'h0C;
    mem[2974] = 8'hF8;
    // glyph 0x74 t
    mem[2976] = 8'h60; mem[2977] = 8'h60; mem[2978] = 8'hF8; mem[2979] = 8'h60;
    mem[2980] = 8'h60; mem[2981] = 8'h6C; mem[2982] = 8'h38;
    // glyph 0x75 u
    mem[2986] = 8'hCC; mem[2987] = 8'hCC; mem[2988] = 8'hCC; mem[2989] = 8'hCC;
    mem[2990] = 8'h7C;
    // glyph 0x76 v
    mem[2994] = 8'hCC; mem[2995] = 8'hCC; mem[2996] = 8'hCC; mem[2997] = 8'h78;
    mem[2998] = 8'h30;
    // glyph 0x77 w
    mem[3002] = 8'hC6; mem[3003] = 8'hD6; mem[3004] = 8'hD6; mem[3005] = 8'hFE;
    mem[3006] = 8'h6C;
    // glyph 0x78 x
    mem[3010] = 8'hCC; mem[3011] = 8'h78; mem[3012] = 8'h30; mem[3013] = 8'h78;
    mem[3014] = 8'hCC;
    // glyph 0x79 y
    mem[3018] = 8'hCC; mem[3019] = 8'hCC; mem[3020] = 8'hCC; mem[3021] = 8'h7C;
    mem[3022] = 8'h0C; mem[3023] = 8'h78;
    // glyph 0x7A z
    mem[3026] = 8'hFC; mem[3027] = 8'h18; mem[3028] = 8'h30; mem[3029] = 8'h60;
    mem[3030] = 8'hFC;
    // glyph 0x7B {
    mem[3032] = 8'h18; mem[3033] = 8'h30; mem[3034] = 8'h30; mem[3035] = 8'h60;
    mem[3036] = 8'h30; mem[3037] = 8'h30; mem[3038] = 8'h18;
    // glyph 0x7C |
    mem[3040] = 8'h30; mem[3041] = 8'h30; mem[3042] = 8'h30; mem[3043] = 8'h30;
    mem[3044] = 8'h30; mem[3045] = 8'h30; mem[3046] = 8'h30;
    // glyph 0x7D }
    mem[3048] = 8'h60; mem[3049] = 8'h30; mem[3050] = 8'h30; mem[3051] = 8'h18;
    mem[3052] = 8'h30; mem[3053] = 8'h30; mem[3054] = 8'h60;
    // glyph 0x7E ~
    mem[3058] = 8'h76; mem[3059] = 8'hDC;
  end

  always_ff @(posedge clk_i) data_o <= mem[addr_i];

endmodule
