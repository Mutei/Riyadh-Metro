// Store all named metro station lists here and import where needed.
// Usage in other files: import 'package:your_app/data/metro_stations.dart' as metro;

library metro_stations;

// Red Line
const List<Map<String, dynamic>> redStations = [
  {
    'name': 'King Saud University',
    'nameAr': 'جامعة الملك سعود',
    'lat': 24.710318604089824,
    'lng': 46.628336697444446
  },
  {
    'name': 'King Salman Oasis',
    'nameAr': 'واحة الملك سلمان',
    'lat': 24.7169961818892,
    'lng': 46.63856726259658
  },
  {
    'name': 'KACST',
    'nameAr': 'المدينة التقنية',
    'lat': 24.72100616920767,
    'lng': 46.64809519952794
  },
  {
    'name': 'Takhasusi',
    'nameAr': 'التخصصي',
    'lat': 24.723765796572632,
    'lng': 46.65466707828979
  },
  {
    'name': 'STC',
    'nameAr': 'STC',
    'lat': 24.72665200393476,
    'lng': 46.66700775672067
  },
  {
    'name': 'Al Wurud',
    'nameAr': 'الورود',
    'lat': 24.73327807626886,
    'lng': 46.6769962747723
  },
  {
    'name': 'King Abdulaziz Road',
    'nameAr': 'طريق الملك عبدالعزيز',
    'lat': 24.736822740098376,
    'lng': 46.6855279591482
  },
  {
    'name': 'Ministry of Education',
    'nameAr': 'وزارة التعليم',
    'lat': 24.740639219799682,
    'lng': 46.694691858874386
  },
  {
    'name': 'An Nuzhah',
    'nameAr': 'النزهة',
    'lat': 24.74808683788983,
    'lng': 46.712270890276564
  },
  {
    'name': 'Riyadh Exhibition Center',
    'nameAr': 'مركز الرياض للمعارض',
    'lat': 24.767520506813426,
    'lng': 46.75865705577289
  },
  {
    'name': 'Khalid Ibn Waleed',
    'nameAr': 'طريق خالد بن الوليد',
    'lat': 24.754520706460326,
    'lng': 46.727107489510345
  },
  {
    'name': 'Hamra',
    'nameAr': 'الحمراء',
    'lat': 24.77638976323128,
    'lng': 46.776786144668115
  },
  {
    'name': 'Al Khaleej',
    'nameAr': 'الخليج',
    'lat': 24.781887833830538,
    'lng': 46.79404005783591
  },
  {
    'name': 'Ishbilyah',
    'nameAr': 'اشبيليا',
    'lat': 24.792416085697525,
    'lng': 46.81114338429113
  },
  {
    'name': 'King Fahd Sport City',
    'nameAr': 'مدينة الملك فهد الرياضية',
    'lat': 24.793091264373807,
    'lng': 46.836708784810135
  },
];

// Yellow Line
const List<Map<String, dynamic>> yellowStations = [
  {
    'name': 'KAFD',
    'nameAr': 'المركز المالي',
    'lat': 24.767196162721014,
    'lng': 46.64292274167118
  },
  {
    'name': 'Al Rabi',
    'nameAr': 'الربيع',
    'lat': 24.786389603560817,
    'lng': 46.66006567579031
  },
  {
    'name': 'Uthman Bin Affan Road',
    'nameAr': 'طريق عثمان بن عفان',
    'lat': 24.801578985211076,
    'lng': 46.6960210762531
  },
  {
    'name': 'SABIC',
    'nameAr': 'سابك',
    'lat': 24.807331028123038,
    'lng': 46.7094440382528
  },
  {
    'name': 'PNU 1',
    'nameAr': 'جامعة الأميرة نورة 1',
    'lat': 24.841479045834085,
    'lng': 46.717410955874584
  },
  {
    'name': 'PNU 2',
    'nameAr': 'جامعة الأميرة نورة 2',
    'lat': 24.85955295107052,
    'lng': 46.70451257453846
  },
  {
    'name': 'Airport T5',
    'nameAr': 'الصالة 5',
    'lat': 24.940744284930975,
    'lng': 46.71037241226726
  },
  {
    'name': 'Airport T3-4',
    'nameAr': 'الصالة 3-4',
    'lat': 24.955992475485093,
    'lng': 46.70225258991898
  },
  {
    'name': 'Airport T1-2',
    'nameAr': 'الصالة 2-1',
    'lat': 24.961000520542694,
    'lng': 46.69899235079351
  },
];

// Purple Line
const List<Map<String, dynamic>> purpleStations = [
  {
    'name': 'KAFD',
    'nameAr': 'المركز المالي',
    'lat': 24.767476415943126,
    'lng': 46.64307080442587
  },
  {
    'name': 'Al Rabi',
    'nameAr': 'الربيع',
    'lat': 24.78628332545239,
    'lng': 46.66017909139241
  },
  {
    'name': 'Uthman Bin Affan Road',
    'nameAr': 'طريق عثمان بن عفان',
    'lat': 24.801408553817193,
    'lng': 46.69613438643552
  },
  {
    'name': 'SABIC',
    'nameAr': 'سابك',
    'lat': 24.807068273040997,
    'lng': 46.70952424995326
  },
  {
    'name': 'Grandia',
    'nameAr': 'غرناطية',
    'lat': 24.78644316972398,
    'lng': 46.72923297240364
  },
  {
    'name': 'Yarmuk',
    'nameAr': 'اليرموك',
    'lat': 24.791309278637172,
    'lng': 46.766240057308195
  },
  {
    'name': 'Hamra',
    'nameAr': 'الحمراء',
    'lat': 24.77638976323128,
    'lng': 46.776786144668115
  },
  {
    'name': 'Al Andalus',
    'nameAr': 'الأندلس',
    'lat': 24.756753397503633,
    'lng': 46.79020403288658
  },
  {
    'name': 'Khurais Road',
    'nameAr': 'طريق خريص',
    'lat': 24.740895116198885,
    'lng': 46.798331141998155
  },
  {
    'name': 'As Salam',
    'nameAr': 'السلام',
    'lat': 24.72270694739788,
    'lng': 46.81120787437414
  },
  {
    'name': 'An Naseem',
    'nameAr': 'النسيم',
    'lat': 24.700530428284306,
    'lng': 46.82751033682791
  },
];

// Blue Line
const List<Map<String, dynamic>> blueStations = [
  {
    'name': 'SAB Bank',
    'nameAr': 'بنك الأول',
    'lat': 24.830277742664208,
    'lng': 46.61566205359704
  },
  {
    'name': 'Dr Sulaiman Al Habib',
    'nameAr': 'د.سليمان الحبيب',
    'lat': 24.811615620023698,
    'lng': 46.62569063077323
  },
  {
    'name': 'KAFD',
    'nameAr': 'الركز المالي',
    'lat': 24.767476415943126,
    'lng': 46.64307080442587
  },
  {
    'name': 'Al Murooj',
    'nameAr': 'المروج',
    'lat': 24.75488360702907,
    'lng': 46.654238136153076
  },
  {
    'name': 'King Fahd District',
    'nameAr': 'حي الملك فهد',
    'lat': 24.745550934792167,
    'lng': 46.65919944758175
  },
  {
    'name': 'King Fahd District 2',
    'nameAr': 'حي الملك فهد 2',
    'lat': 24.736597048505566,
    'lng': 46.663507594807385
  },
  {
    'name': 'STC',
    'nameAr': 'STC',
    'lat': 24.72665200393476,
    'lng': 46.66700775672067
  },
  {
    'name': 'Al Wurud 2',
    'nameAr': 'الورود 2',
    'lat': 24.7212803513824,
    'lng': 46.67125340515732
  },
  {
    'name': 'Al Urubah',
    'nameAr': 'العروبة',
    'lat': 24.713918655497036,
    'lng': 46.67495358550864
  },
  {
    'name': 'Alinma Bank',
    'nameAr': 'مصرف الإنماء',
    'lat': 24.70352714676529,
    'lng': 46.68017543626166
  },
  {
    'name': 'Al Bilad Bank',
    'nameAr': 'بنك البلاد',
    'lat': 24.69667137736483,
    'lng': 46.68369783505113
  },
  {
    'name': 'King Fahd Library',
    'nameAr': 'مكتبة الملك فهد',
    'lat': 24.690244975419038,
    'lng': 46.68711717491829
  },
  {
    'name': 'Ministry of Interior',
    'nameAr': 'وزارة الداخلية',
    'lat': 24.674487891468,
    'lng': 46.69490351521827
  },
  {
    'name': 'Al Murabba',
    'nameAr': 'المربع',
    'lat': 24.664931724116833,
    'lng': 46.702305438075356
  },
  {
    'name': 'Passport Department',
    'nameAr': 'الجوازات',
    'lat': 24.65980304746202,
    'lng': 46.70425691826859
  },
  {
    'name': 'National Museum',
    'nameAr': 'المتحف الوطني',
    'lat': 24.645251678247988,
    'lng': 46.71310268991183
  },
  {
    'name': 'Al Batha',
    'nameAr': 'البطجاء',
    'lat': 24.63687191262214,
    'lng': 46.714732620987824
  },
  {
    'name': 'Qasr Al Hokm',
    'nameAr': 'قصر الحكم',
    'lat': 24.628923733369177,
    'lng': 46.7163116166964
  },
  {
    'name': 'Al Owd',
    'nameAr': 'العود',
    'lat': 24.62569801739273,
    'lng': 46.721422129637965
  },
  {
    'name': 'Skirinah',
    'nameAr': 'سكيرينة',
    'lat': 24.617918914910682,
    'lng': 46.72525925905265
  },
  {
    'name': 'Manfouhah',
    'nameAr': 'منفوحة',
    'lat': 24.610540668150893,
    'lng': 46.72751739278078
  },
  {
    'name': 'Al Iman Hospital',
    'nameAr': 'مستشفى الإيمان',
    'lat': 24.60046047705138,
    'lng': 46.73583683245633
  },
  {
    'name': 'Transportation Center',
    'nameAr': 'مركز النقل العام',
    'lat': 24.598237477252123,
    'lng': 46.745107065286255
  },
  {
    'name': 'Aziziya',
    'nameAr': 'العزيزية',
    'lat': 24.587257452936473,
    'lng': 46.76082096705217
  },
  {
    'name': 'Ad Dar Al Baida',
    'nameAr': 'الدار البيضاء',
    'lat': 24.559973831320452,
    'lng': 46.77636196816308
  },
];

// Orange Line
const List<Map<String, dynamic>> orangeStations = [
  {
    'name': 'Khasm Al An',
    'nameAr': 'خشم العان',
    'lat': 24.72113821847048,
    'lng': 46.86014578328242
  },
  {
    'name': 'Hasan Bin Thabit',
    'nameAr': 'شارع حسان بن ثابت',
    'lat': 24.712710978139686,
    'lng': 46.847478330726645
  },
  {
    'name': 'An Naseem',
    'nameAr': 'النسيم',
    'lat': 24.700473980778924,
    'lng': 46.827564018821164
  },
  {
    'name': 'Harun Al Rashid Road',
    'nameAr': 'طريق هارون الرشيد',
    'lat': 24.68607919498442,
    'lng': 46.79594500125352
  },
  {
    'name': 'Al Rajhi Grand Mosque',
    'nameAr': 'جامع الراجحي',
    'lat': 24.680210809164926,
    'lng': 46.779405022731396
  },
  {
    'name': 'Jarir District',
    'nameAr': 'حي جرير',
    'lat': 24.673096004214408,
    'lng': 46.76037461533075
  },
  {
    'name': 'Al Malaz',
    'nameAr': 'الملز',
    'lat': 24.661470006135318,
    'lng': 46.744804265769076
  },
  {
    'name': 'Railway',
    'nameAr': 'سكة الحديد',
    'lat': 24.649571016686135,
    'lng': 46.74056303216547
  },
  {
    'name': 'First Industrial City',
    'nameAr': 'المدينة الصناعية الأولى',
    'lat': 24.64560695031045,
    'lng': 46.739323912391974
  },
  {
    'name': 'As Salhiyah',
    'nameAr': 'الصالحية',
    'lat': 24.637833340359734,
    'lng': 46.732972665295705
  },
  {
    'name': 'Al Margab',
    'nameAr': 'المرقب',
    'lat': 24.634515591070553,
    'lng': 46.72630358166753
  },
  {
    'name': 'Al Hilla',
    'nameAr': 'الحلة',
    'lat': 24.632332830132743,
    'lng': 46.721903038690826
  },
  {
    'name': 'Qasr Al Hokm',
    'nameAr': 'قصر الحكم',
    'lat': 24.62895349346273,
    'lng': 46.71625597988287
  },
  {
    'name': 'Courts Complex',
    'nameAr': 'مجمع المحاكم',
    'lat': 24.626908278506196,
    'lng': 46.712546788912206
  },
  {
    'name': 'Al Jarradiyah',
    'nameAr': 'الجرادية',
    'lat': 24.618668901385984,
    'lng': 46.69874281797616
  },
  {
    'name': 'Sultanah',
    'nameAr': 'سلطانة',
    'lat': 24.614961662084916,
    'lng': 46.6864732446278
  },
  {
    'name': 'Dharat Al Badiah',
    'nameAr': 'ظهرة البديعة',
    'lat': 24.60673989020932,
    'lng': 46.65378486989474
  },
  {
    'name': 'Aishah Bint Abi Bakr',
    'nameAr': 'شارع عائشة بنت ابي بكر',
    'lat': 24.600603601065334,
    'lng': 46.643780230848975
  },
  {
    'name': 'Western',
    'nameAr': 'المحطة الغربية',
    'lat': 24.58184593482687,
    'lng': 46.614546473161276
  },
  {
    'name': 'Ad Douh',
    'nameAr': 'الدوح',
    'lat': 24.582599377175764,
    'lng': 46.58834499445341
  },
  {
    'name': 'Tuwaiq',
    'nameAr': 'طويق',
    'lat': 24.5854678307825,
    'lng': 46.55970195423734
  },
  {
    'name': 'Jeddah Road',
    'nameAr': 'طريق جده',
    'lat': 24.591408611278148,
    'lng': 46.54354336979688
  },
];

// Green Line
const List<Map<String, dynamic>> greenStations = [
  {
    'name': 'Ministry of Education',
    'nameAr': 'وزارة التعليم',
    'lat': 24.74015201628307,
    'lng': 46.69485117697147,
  },
  {
    'name': 'King Salman Park',
    'nameAr': 'حديقة الملك سلمان',
    'lat': 24.72817060272514,
    'lng': 46.70092461638526
  },
  {
    'name': 'As Sulaimaniya',
    'nameAr': 'السليمانية',
    'lat': 24.71279876354132,
    'lng': 46.700348460925376
  },
  {
    'name': 'Ad Dabab',
    'nameAr': 'الضباب',
    'lat': 24.709757046156152,
    'lng': 46.707609074366204
  },
  {
    'name': 'Abu Dhabi Square',
    'nameAr': 'ميدان أبو ظبي',
    'lat': 24.70608156224649,
    'lng': 46.71648789940656
  },
  {
    'name': 'Officers Club',
    'nameAr': 'نادي الضباط',
    'lat': 24.69798005200728,
    'lng': 46.71787845780667
  },
  {
    'name': 'GOSI Complex',
    'nameAr': 'التأمينات الإجتماعية',
    'lat': 24.68634537123963,
    'lng': 46.71813369626534
  },
  {
    'name': 'Al Wizarat',
    'nameAr': 'الوزارات',
    'lat': 24.67602141694447,
    'lng': 46.71839138879093
  },
  {
    'name': 'Ministry of Defense',
    'nameAr': 'وزارة الدفاع',
    'lat': 24.668122888335535,
    'lng': 46.718213444156056
  },
  {
    'name': 'King Abdulaziz Hospital',
    'nameAr': 'مستشفى الملك عبدالعزيز',
    'lat': 24.659673181925132,
    'lng': 46.71770259088508
  },
  {
    'name': 'Ministry of Finance',
    'nameAr': 'وزارة المالية',
    'lat': 24.652107502718454,
    'lng': 46.716312577252054
  },
  {
    'name': 'National Museum',
    'nameAr': 'المتحف الوطني',
    'lat': 24.645251678247988,
    'lng': 46.71310268991183
  },
];
