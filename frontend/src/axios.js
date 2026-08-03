import axios from 'axios';

// Пустая строка = относительные пути, запросы идут на тот же origin, что и сам сайт,
// и попадают в backend через nginx (/api/, /moderator/, /images/, /news, /projects).
// Абсолютный http://...:1337 нельзя: на HTTPS-странице браузер блокирует такой запрос
// как mixed content, плюс порт 1337 наружу больше не проброшен.
// Значение задаётся на этапе сборки: build-arg REACT_APP_API_URL в compose.yml.
const baseURL = process.env.REACT_APP_API_URL || '';

export const instance = axios.create({
    baseURL,
});

instance.interceptors.request.use((config) => {
    config.headers.Authorization = window.localStorage.getItem('token');
    return config;
});

export default baseURL;
