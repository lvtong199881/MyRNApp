import React from 'react';
import {View, Text, StyleSheet, TouchableOpacity, Alert} from 'react-native';

interface Props {
  message?: string;
}

const MyRNPage: React.FC<Props> = ({message = '来自 Android 的问候'}) => {
  const handlePress = () => {
    Alert.alert('RN 按钮点击', 'React Native 页面正常工作!');
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>我是 React Native 页面</Text>
        <Text style={styles.subtitle}>Android 组件化项目</Text>
      </View>

      <View style={styles.content}>
        <Text style={styles.message}>{message}</Text>
        
        <TouchableOpacity style={styles.button} onPress={handlePress}>
          <Text style={styles.buttonText}>点击测试</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.footer}>
        <Text style={styles.version}>RN Version: 0.76.9</Text>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  header: {
    backgroundColor: '#2196F3',
    padding: 20,
    paddingTop: 40,
    alignItems: 'center',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: 'white',
  },
  subtitle: {
    fontSize: 14,
    color: 'rgba(255,255,255,0.8)',
    marginTop: 4,
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  message: {
    fontSize: 18,
    color: '#333',
    textAlign: 'center',
    marginBottom: 30,
  },
  button: {
    backgroundColor: '#4CAF50',
    paddingHorizontal: 30,
    paddingVertical: 15,
    borderRadius: 8,
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
  footer: {
    padding: 15,
    alignItems: 'center',
  },
  version: {
    fontSize: 12,
    color: '#999',
  },
});

export default MyRNPage;
