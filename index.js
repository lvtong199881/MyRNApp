/**
 * @format
 */

import {AppRegistry} from 'react-native';
import App from './src/App';
import {name as appName} from './app.json';

// 注册主组件（Android 通过这个名称调用）
AppRegistry.registerComponent('MyRNApp', () => App);
