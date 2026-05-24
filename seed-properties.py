# -*- coding: utf-8 -*-
"""
Seed 30 diverse Moscow properties for the landlord (id=5).
For each property: download 2-3 AI-generated images from Pollinations (with fallback)
and insert rows into properties + property_images tables.
"""

import io
import os
import random
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import quote

import psycopg2
import requests
from PIL import Image, ImageDraw, ImageFont

# clear stale TLS envs that break requests
for k in ('REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE', 'SSL_CERT_FILE'):
    os.environ.pop(k, None)

LANDLORD_ID = 5
UPLOADS = r'C:\Games\street-retail-aggregator\backend\uploads'

PROPERTIES = [
    # центр
    dict(title='ПСН с витриной на Тверской, 95 м²', address='Москва, ул. Тверская, 5/6',
         lat=55.7654, lng=37.6056, metro='Тверская', time_to_metro=2,
         type='PSN', area=95, price=380000, floor=1, total_floors=7, build_year=1936, building_class='B_PLUS',
         desc='Светлое помещение с витринным остеклением на первой линии Тверской улицы. Высокий пешеходный трафик, идеально для кафе, бутика, шоурума.'),
    dict(title='Помещение под ресторан у Чистых прудов, 140 м²', address='Москва, ул. Покровка, 17с1',
         lat=55.7611, lng=37.6386, metro='Чистые пруды', time_to_metro=4,
         type='CATERING', area=140, price=520000, floor=1, total_floors=5, build_year=1903, building_class='B',
         desc='Готовое заведение общепита с вытяжкой 10000 м³/ч, мойкой, действующей лицензией на алкоголь у предыдущего арендатора. Витрина на бульвар.'),
    dict(title='Бутик на Арбате, 65 м²', address='Москва, ул. Арбат, 31',
         lat=55.7494, lng=37.5959, metro='Арбатская', time_to_metro=3,
         type='RETAIL', area=65, price=290000, floor=1, total_floors=4, build_year=1912, building_class='B',
         desc='Помещение в пешеходной зоне на самом проходном участке Арбата. Витрина 6 метров, отдельный вход, цокольный этаж под склад.'),
    dict(title='Офис класса A у Лубянки, 220 м²', address='Москва, ул. Мясницкая, 13с1',
         lat=55.7595, lng=37.6285, metro='Лубянка', time_to_metro=5,
         type='OFFICE', area=220, price=880000, floor=4, total_floors=8, build_year=2008, building_class='A',
         desc='Современный офис в бизнес-центре класса A. Open space + переговорные, дизайнерская отделка, серверная, 24/7 доступ, охрана, паркинг.'),
    dict(title='Магазин на Маяковской, 80 м²', address='Москва, 1-я Тверская-Ямская, 11',
         lat=55.7706, lng=37.5953, metro='Маяковская', time_to_metro=3,
         type='RETAIL', area=80, price=360000, floor=1, total_floors=9, build_year=1970, building_class='B',
         desc='Помещение с двумя витринами на первой линии. Подходит под продуктовый, пекарню, барбершоп, цветочный.'),
    dict(title='Кофейня у Кропоткинской, 110 м²', address='Москва, ул. Остоженка, 6с2',
         lat=55.7458, lng=37.6042, metro='Кропоткинская', time_to_metro=4,
         type='CATERING', area=110, price=410000, floor=1, total_floors=6, build_year=1898, building_class='B_PLUS',
         desc='Историческое здание в районе Хамовники. Высокие потолки 4.2 м, лепнина сохранена, инженерия обновлена. Прекрасное место под концептуальную кофейню.'),

    # сити
    dict(title='Офис в Москва-Сити, башня Федерация, 450 м²', address='Москва, Пресненская наб., 12',
         lat=55.7497, lng=37.5398, metro='Деловой центр', time_to_metro=2,
         type='OFFICE', area=450, price=1800000, floor=42, total_floors=95, build_year=2017, building_class='A',
         desc='Премиальный офис на 42 этаже Федерации. Панорамное остекление на Москва-реку, дизайнерский ремонт, мебель Vitra, переговорные с видеоконференцией.'),
    dict(title='Офис класса B+ в Сити, 180 м²', address='Москва, 1-й Красногвардейский пр., 21с1',
         lat=55.7497, lng=37.5398, metro='Выставочная', time_to_metro=5,
         type='OFFICE', area=180, price=540000, floor=12, total_floors=24, build_year=2014, building_class='B_PLUS',
         desc='Готовый офис рядом с Москва-Сити. Open space на 30 рабочих мест, переговорная, кухня, две входные группы.'),
    dict(title='Представительский офис на Краснопресненской, 320 м²', address='Москва, ул. Заморёнова, 9с1',
         lat=55.7615, lng=37.5783, metro='Краснопресненская', time_to_metro=6,
         type='OFFICE', area=320, price=1100000, floor=5, total_floors=7, build_year=2010, building_class='A',
         desc='Особняк с собственным паркингом. Кабинетная планировка, мраморный ресепшн, серверная, ВИП-переговорные. Идеально для головного офиса.'),
    dict(title='Офис в шаговой доступности от Беговой, 95 м²', address='Москва, Ленинградский пр., 31',
         lat=55.7732, lng=37.5479, metro='Беговая', time_to_metro=4,
         type='OFFICE', area=95, price=220000, floor=3, total_floors=5, build_year=1985, building_class='B',
         desc='Бюджетный офис рядом с метро. Косметический ремонт, мебель в наличии. Хороший вариант для стартапа или представительства.'),

    # север
    dict(title='Аптека у метро Сокол, 50 м²', address='Москва, Ленинградский пр., 75к1',
         lat=55.8048, lng=37.5147, metro='Сокол', time_to_metro=1,
         type='RETAIL', area=50, price=145000, floor=1, total_floors=14, build_year=1960, building_class='C',
         desc='Помещение под аптеку или мини-маркет. Витрина выходит на остановку общественного транспорта, проходимость 8000 человек в сутки.'),
    dict(title='Магазин у дороги, м. Аэропорт, 70 м²', address='Москва, Ленинградский пр., 62А',
         lat=55.7995, lng=37.5316, metro='Аэропорт', time_to_metro=6,
         type='PSN', area=70, price=175000, floor=1, total_floors=9, build_year=1972, building_class='C',
         desc='Помещение с двумя входами (с улицы и со двора). Подходит под автозапчасти, шиномонтаж, сервисный центр.'),
    dict(title='Заведение у стадиона Динамо, 130 м²', address='Москва, Ленинградский пр., 36с36',
         lat=55.7895, lng=37.5589, metro='Динамо', time_to_metro=3,
         type='CATERING', area=130, price=360000, floor=1, total_floors=4, build_year=2016, building_class='B_PLUS',
         desc='Современное заведение рядом со стадионом ВТБ Арена. Готовые коммуникации общепита, летняя терраса на 40 посадочных мест.'),
    dict(title='Склад в Войковском, 600 м², рампа', address='Москва, ул. Космодемьянских, 31А',
         lat=55.8189, lng=37.4995, metro='Войковская', time_to_metro=15,
         type='WAREHOUSE', area=600, price=480000, floor=1, total_floors=2, build_year=2005, building_class='B',
         desc='Отапливаемый склад с рампой на грузовик. Потолки 8 м, антипылевое покрытие, стеллажи в подарок. Удобный заезд с Ленинградского ш.'),
    dict(title='Помещение на Алексеевской, 85 м²', address='Москва, пр-т Мира, 95',
         lat=55.8074, lng=37.6383, metro='Алексеевская', time_to_metro=2,
         type='RETAIL', area=85, price=195000, floor=1, total_floors=12, build_year=1978, building_class='C',
         desc='Помещение с витринным остеклением 8 м. Хороший трафик, рядом школа, бизнес-центр и жилые дома.'),

    # восток
    dict(title='Барбершоп в Сокольниках, 75 м²', address='Москва, Стромынка, 14',
         lat=55.7884, lng=37.6797, metro='Сокольники', time_to_metro=4,
         type='RETAIL', area=75, price=230000, floor=1, total_floors=6, build_year=1996, building_class='B',
         desc='Помещение со свежим ремонтом, готовое под барбершоп или салон. 5 рабочих мест уже размечены, мойка, душевая, гардероб.'),
    dict(title='Преображенская площадь, ПСН 110 м²', address='Москва, ул. Большая Черкизовская, 5',
         lat=55.7958, lng=37.7148, metro='Преображенская площадь', time_to_metro=3,
         type='PSN', area=110, price=250000, floor=1, total_floors=8, build_year=1981, building_class='C',
         desc='Угловое помещение с двумя входами. Подходит под клинику, образовательный центр, спорт-зону.'),
    dict(title='Магазин у Семёновской, 60 м²', address='Москва, Семёновская пл., 1',
         lat=55.7826, lng=37.7195, metro='Семёновская', time_to_metro=2,
         type='RETAIL', area=60, price=165000, floor=1, total_floors=5, build_year=1969, building_class='C',
         desc='Компактное помещение с витриной. Близко к метро, ТЦ Семёновский, жилой массив. Подходит под цветы, выпечку, кофе с собой.'),
    dict(title='Заведение у Партизанской, 95 м²', address='Москва, Измайловское шоссе, 71к4',
         lat=55.7878, lng=37.7493, metro='Партизанская', time_to_metro=5,
         type='CATERING', area=95, price=245000, floor=1, total_floors=4, build_year=2003, building_class='B',
         desc='Помещение рядом с Измайловским Кремлём и Вернисажем. Постоянный поток туристов, есть зона под летнюю террасу.'),
    dict(title='Офис на Курской, 140 м²', address='Москва, ул. Земляной Вал, 9',
         lat=55.7574, lng=37.6612, metro='Курская', time_to_metro=3,
         type='OFFICE', area=140, price=350000, floor=4, total_floors=9, build_year=2002, building_class='B_PLUS',
         desc='Удобный офис в БЦ "Земляной Вал". Кабинетная планировка, ресепшн, переговорная, кондиционирование, опт.-волокно.'),

    # юг/восток
    dict(title='Ресторан на Таганке, 85 м²', address='Москва, ул. Таганская, 32',
         lat=55.7416, lng=37.6537, metro='Таганская', time_to_metro=3,
         type='CATERING', area=85, price=290000, floor=1, total_floors=5, build_year=1995, building_class='B',
         desc='Готовый ресторан с действующим оборудованием. Кухня, бар, посадочная зона на 45 мест, веранда. Алкогольная лицензия в процессе переоформления.'),
    dict(title='Магазин у Марксистской, 70 м²', address='Москва, ул. Марксистская, 5',
         lat=55.7421, lng=37.6644, metro='Марксистская', time_to_metro=2,
         type='RETAIL', area=70, price=195000, floor=1, total_floors=12, build_year=1985, building_class='C',
         desc='Помещение с витриной на первой линии. Высокий пешеходный трафик от метро, рядом ТЦ, продуктовый, банк.'),
    dict(title='Склад в Печатниках, 1200 м²', address='Москва, ул. Шоссейная, 70',
         lat=55.6936, lng=37.7299, metro='Печатники', time_to_metro=12,
         type='WAREHOUSE', area=1200, price=720000, floor=1, total_floors=1, build_year=2010, building_class='B',
         desc='Большой отапливаемый склад с двумя рампами, кран-балка 5 тонн, антипылевой пол. Удобный заезд для фуры, охраняемая территория.'),
    dict(title='Производство в Текстильщиках, 850 м²', address='Москва, Волгоградский пр., 42',
         lat=55.7102, lng=37.7321, metro='Текстильщики', time_to_metro=8,
         type='PRODUCTION', area=850, price=510000, floor=1, total_floors=2, build_year=1998, building_class='C',
         desc='Производственное помещение с высокими потолками 7 м, мощностью 150 кВт, тельфером. Подойдёт для лёгкого производства, цеха, мастерской.'),
    dict(title='ПСН у Кожуховской, 130 м²', address='Москва, ул. Южнопортовая, 22',
         lat=55.7066, lng=37.6783, metro='Кожуховская', time_to_metro=4,
         type='PSN', area=130, price=240000, floor=1, total_floors=6, build_year=1984, building_class='C',
         desc='Помещение свободного назначения с отдельным входом. Идеально под автошколу, медицинский центр, образовательный проект.'),

    # запад / юго-запад
    dict(title='Кафе на Молодёжной, 120 м²', address='Москва, ул. Ярцевская, 22к1',
         lat=55.7402, lng=37.4159, metro='Молодёжная', time_to_metro=3,
         type='CATERING', area=120, price=295000, floor=1, total_floors=10, build_year=1979, building_class='B',
         desc='Готовое кафе рядом с метро и ТЦ "Кунцево Плаза". Витрина, веранда, оборудованная кухня, парковка для гостей.'),
    dict(title='Магазин у Юго-Западной, 95 м²', address='Москва, пр-т Вернадского, 86',
         lat=55.6630, lng=37.4838, metro='Юго-Западная', time_to_metro=2,
         type='RETAIL', area=95, price=240000, floor=1, total_floors=9, build_year=1976, building_class='B',
         desc='Витринное помещение рядом с метро. Высокий трафик студентов МГИМО и жителей. Подходит под продукты, аптеку, цветы.'),
    dict(title='Офис класса B+ у Университета, 200 м²', address='Москва, Ленинский пр., 70/11',
         lat=55.6924, lng=37.5347, metro='Университет', time_to_metro=5,
         type='OFFICE', area=200, price=580000, floor=6, total_floors=12, build_year=2011, building_class='B_PLUS',
         desc='Офис в современном БЦ. Свежий ремонт, кондиционирование, круглосуточный доступ, охрана, паркинг в подарок (4 м/м).'),
    dict(title='Магазин у Парка культуры, 65 м²', address='Москва, Зубовский б-р, 13',
         lat=55.7355, lng=37.5933, metro='Парк культуры', time_to_metro=3,
         type='RETAIL', area=65, price=285000, floor=1, total_floors=6, build_year=1948, building_class='B',
         desc='Историческое здание сталинской постройки. Высокие потолки, лепнина, витражные окна. Высокая концентрация платёжеспособной аудитории.'),
    dict(title='ПСН в Хамовниках, 180 м²', address='Москва, Комсомольский пр., 28',
         lat=55.7330, lng=37.5757, metro='Фрунзенская', time_to_metro=5,
         type='PSN', area=180, price=540000, floor=1, total_floors=8, build_year=1955, building_class='B_PLUS',
         desc='Просторное помещение в респектабельном районе. Подходит под медицинский центр, фитнес-студию, образовательный центр.'),
]

assert len(PROPERTIES) == 30, f'expected 30, got {len(PROPERTIES)}'

PROMPT_BY_TYPE = {
    'OFFICE':     'modern empty office interior, large windows, daylight, business district, no people, photo',
    'RETAIL':     'empty retail store interior, showcase windows facing street, modern minimalist design, no people, photo',
    'WAREHOUSE':  'large warehouse interior with high ceiling, racks, concrete floor, daylight, no people, photo',
    'PRODUCTION': 'industrial production hall interior with light machinery, high ceiling, daylight, no people, photo',
    'PSN':        'empty commercial premises interior, white walls, large windows facing street, modern, no people, photo',
    'CATERING':   'empty restaurant interior, modern design, tables and chairs, soft light, no people, photo',
}
ANGLE_HINTS = ['wide angle', 'side view', 'view from entrance', 'corner perspective']


def pollinations_url(prompt: str, seed: int) -> str:
    enc = quote(prompt, safe='')
    return f'https://image.pollinations.ai/prompt/{enc}?width=1024&height=768&nologo=true&seed={seed}'


def fallback_png(prop, variant) -> bytes:
    palette = {
        'OFFICE': (44, 88, 140), 'RETAIL': (200, 120, 40), 'WAREHOUSE': (90, 90, 100),
        'PRODUCTION': (130, 60, 50), 'PSN': (60, 130, 100), 'CATERING': (170, 70, 90),
    }
    bg = palette.get(prop['type'], (60, 80, 120))
    img = Image.new('RGB', (1024, 768), color=bg)
    d = ImageDraw.Draw(img)
    for y in range(0, 768, 4):
        shade = int(255 * (1 - y / 1500))
        d.line([(0, y), (1024, y)], fill=(min(255, bg[0]+shade//6), min(255, bg[1]+shade//6), min(255, bg[2]+shade//6)))
    d.rectangle([60, 480, 964, 700], fill=(255, 255, 255))
    try:
        font_big = ImageFont.truetype('arial.ttf', 36)
        font_small = ImageFont.truetype('arial.ttf', 22)
    except OSError:
        font_big = ImageFont.load_default()
        font_small = ImageFont.load_default()
    d.text((90, 510), prop['title'], fill=(20, 20, 20), font=font_big)
    d.text((90, 580), f"{prop['address']}", fill=(60, 60, 60), font=font_small)
    d.text((90, 620), f"м. {prop['metro']}  ·  {prop['area']} м²  ·  {prop['price']:,} ₽/мес".replace(',', ' '),
           fill=(60, 60, 60), font=font_small)
    d.text((90, 660), f'Вариант {variant + 1}', fill=(120, 120, 120), font=font_small)
    bio = io.BytesIO()
    img.save(bio, 'PNG')
    return bio.getvalue()


def fetch_image(prop, variant) -> bytes:
    base_prompt = PROMPT_BY_TYPE.get(prop['type'], 'commercial premises interior')
    angle = ANGLE_HINTS[variant % len(ANGLE_HINTS)]
    prompt = f"{base_prompt}, {angle}"
    seed = abs(hash((prop['title'], variant))) % 1000000
    url = pollinations_url(prompt, seed)
    try:
        r = requests.get(url, timeout=90)
        if r.status_code == 200 and r.content and len(r.content) > 5000:
            return r.content
    except Exception as e:
        print(f'   pollinations fail for {prop["title"][:30]} v{variant}: {e}', flush=True)
    return fallback_png(prop, variant)


def main():
    conn = psycopg2.connect(host='localhost', port=5434, user='myuser',
                            password='mypassword', dbname='retail_aggregator')
    conn.autocommit = False
    cur = conn.cursor()

    print(f'Inserting {len(PROPERTIES)} properties for landlord_id={LANDLORD_ID}', flush=True)
    t0 = time.time()

    # Insert all properties first to get IDs
    inserted = []
    for i, p in enumerate(PROPERTIES):
        rs_choices = ['SHELL_AND_CORE', 'TYPICAL', 'DESIGNER', 'PRE_FINISHING']
        rs = random.Random(p['title']).choice(rs_choices)
        layout = random.Random(p['title'] + 'l').choice(['OPEN_SPACE', 'CABINET', 'MIXED'])
        access = random.Random(p['title'] + 'a').choice(['FREE', 'SCHEDULE', 'PASS'])
        heating = random.Random(p['title'] + 'h').choice(['CENTRAL', 'AUTONOMOUS'])
        furniture = random.Random(p['title'] + 'f').choice(['EMPTY', 'FURNISHED', 'READY_BUSINESS'])
        deal = 'SUBLEASE' if i % 8 == 7 else 'DIRECT_LEASE'
        power = {'OFFICE': 25, 'RETAIL': 20, 'WAREHOUSE': 80, 'PRODUCTION': 150,
                 'PSN': 30, 'CATERING': 60}.get(p['type'], 30)
        ceiling = {'OFFICE': 3.0, 'RETAIL': 3.5, 'WAREHOUSE': 8.0, 'PRODUCTION': 7.0,
                   'PSN': 3.5, 'CATERING': 3.5}.get(p['type'], 3.2)

        cur.execute("""
            INSERT INTO properties (
                landlord_id, title, description, address, latitude, longitude,
                area_sqm, price_per_month, status,
                property_type, deal_type, building_class, floor, total_floors, build_year,
                tax_included, opex_included, utility_included, deposit_months, rent_holidays, legal_address_provided,
                metro_station, time_to_metro,
                power_kw, has_water, has_ventilation, has_separate_entrance, repair_state, ceiling_height, layout,
                parking, security, has_wc, has_parking, has_loading_zone,
                contact_name, contact_phone, agent_fee,
                access_type, heating_type, furniture_state, is_occupied,
                building_name
            ) VALUES (
                %s, %s, %s, %s, %s, %s,
                %s, %s, 'PUBLISHED',
                %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s,
                %s, %s,
                %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s,
                %s, %s, %s,
                %s, %s, %s, %s,
                %s
            ) RETURNING id
        """, (
            LANDLORD_ID, p['title'], p['desc'], p['address'], p['lat'], p['lng'],
            p['area'], p['price'],
            p['type'], deal, p['building_class'], p['floor'], p['total_floors'], p['build_year'],
            True, deal == 'DIRECT_LEASE', False, 1 + i % 3, i % 4 == 0, p['type'] == 'OFFICE',
            p['metro'], p['time_to_metro'],
            power, True, p['type'] in ('CATERING', 'PRODUCTION', 'OFFICE'), p['floor'] == 1,
            rs, ceiling, layout,
            'Уличная парковка' if i % 3 else 'Подземный паркинг (платно)',
            'Круглосуточная охрана и видеонаблюдение' if i % 2 == 0 else 'Видеонаблюдение',
            True, i % 3 == 0, p['type'] in ('WAREHOUSE', 'PRODUCTION', 'RETAIL'),
            'Магомед', '+7 (999) 123-45-67', 0 if i % 5 == 0 else 50,
            access, heating, furniture, False,
            f"БЦ/ТЦ на {p['metro']}" if p['type'] != 'WAREHOUSE' else None,
        ))
        pid = cur.fetchone()[0]
        inserted.append((pid, p))
        print(f'  [{i+1}/30] id={pid}  {p["title"]}', flush=True)

    conn.commit()
    print(f'All properties inserted in {time.time()-t0:.1f}s. Now fetching images...', flush=True)

    # Build image tasks
    tasks = []
    for pid, p in inserted:
        n_images = 2 + (pid % 2)  # 2 or 3 images per property
        for v in range(n_images):
            tasks.append((pid, p, v))
    print(f'Total image tasks: {len(tasks)}. Parallelism: 8.', flush=True)

    saved = []
    t_img = time.time()
    done_count = [0]

    def work(task):
        pid, p, v = task
        data = fetch_image(p, v)
        pdir = os.path.join(UPLOADS, 'properties', str(pid))
        os.makedirs(pdir, exist_ok=True)
        fname = f'{uuid.uuid4()}.png'
        with open(os.path.join(pdir, fname), 'wb') as f:
            f.write(data)
        done_count[0] += 1
        if done_count[0] % 5 == 0:
            print(f'  images: {done_count[0]}/{len(tasks)} elapsed={time.time()-t_img:.0f}s', flush=True)
        return (pid, fname, v == 0)

    with ThreadPoolExecutor(max_workers=8) as ex:
        for result in ex.map(work, tasks):
            saved.append(result)

    print(f'All images downloaded in {time.time()-t_img:.0f}s. Inserting rows...', flush=True)

    # Group images by property, sort so v=0 (main) is first
    by_prop = {}
    for pid, fname, is_main in saved:
        by_prop.setdefault(pid, []).append((fname, is_main))

    for pid, items in by_prop.items():
        for fname, is_main in items:
            url = f'/uploads/properties/{pid}/{fname}'
            cur.execute("INSERT INTO property_images (property_id, image_url, is_main) VALUES (%s, %s, %s)",
                        (pid, url, is_main))
    conn.commit()
    print(f'Done. Total: {time.time()-t0:.0f}s', flush=True)

    cur.execute("SELECT COUNT(*) FROM properties WHERE landlord_id=%s", (LANDLORD_ID,))
    print(f'Properties in DB for landlord {LANDLORD_ID}: {cur.fetchone()[0]}', flush=True)
    cur.execute("""SELECT COUNT(*) FROM property_images pi
                   JOIN properties p ON p.id=pi.property_id
                   WHERE p.landlord_id=%s""", (LANDLORD_ID,))
    print(f'Images in DB: {cur.fetchone()[0]}', flush=True)

    cur.close()
    conn.close()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
